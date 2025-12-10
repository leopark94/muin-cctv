"""Real-time detection worker for multi-store CCTV seat monitoring."""
import os
import sys
import time
import signal
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional
from multiprocessing import Process, Queue, Event
from collections import defaultdict

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from src.config import settings
from src.utils import RTSPClient
from src.core import PersonDetector, ROIMatcher
from src.database.supabase_client import get_supabase_client
from dotenv import load_dotenv

load_dotenv()


class ChannelWorker:
    """Worker for monitoring a single RTSP channel."""

    def __init__(
        self,
        store_id: str,
        channel_id: int,
        rtsp_url: str,
        stop_event: Event,
        snapshot_interval: int = 3
    ):
        """Initialize channel worker.

        Args:
            store_id: Store identifier
            channel_id: Channel number (1-16)
            rtsp_url: RTSP stream URL
            stop_event: Multiprocessing event for graceful shutdown
            snapshot_interval: Seconds between snapshots
        """
        self.store_id = store_id
        self.channel_id = channel_id
        self.rtsp_url = rtsp_url
        self.stop_event = stop_event
        self.snapshot_interval = snapshot_interval

        # Initialize clients (will be created in worker process)
        self.rtsp_client = None
        self.detector = None
        self.roi_matcher = None
        self.db = None

        # State tracking
        self.previous_occupancy = {}
        self.abandoned_timers = defaultdict(float)  # seat_id -> elapsed time with object only

    def initialize(self):
        """Initialize resources (must be called in worker process)."""
        print(f"[Channel {self.channel_id}] Initializing...")

        # RTSP client
        self.rtsp_client = RTSPClient(self.rtsp_url)

        # YOLO detector
        self.detector = PersonDetector(
            model_path=settings.YOLO_MODEL,
            confidence=settings.CONFIDENCE_THRESHOLD
        )

        # Database client
        self.db = get_supabase_client()

        # Load ROI configuration from database
        seats = self.db.get_seats(self.store_id, active_only=True)
        channel_seats = [s for s in seats if s.get('channel_id') == self.channel_id]

        if not channel_seats:
            print(f"[Channel {self.channel_id}] ⚠️  No seats configured for this channel")
            return False

        # Build ROI config for matcher
        roi_config = {
            "camera_id": f"{self.store_id}_channel_{self.channel_id}",
            "resolution": [1920, 1080],
            "seats": [
                {
                    "id": s['seat_id'],
                    "roi": s['roi_polygon'],
                    "label": s.get('seat_label', s['seat_id']),
                    "type": "polygon"
                }
                for s in channel_seats
                if s.get('roi_polygon') and len(s['roi_polygon']) > 0
            ]
        }

        if not roi_config['seats']:
            print(f"[Channel {self.channel_id}] ⚠️  No ROI polygons configured")
            return False

        self.roi_matcher = ROIMatcher(roi_config)

        # Initialize previous state
        for seat in roi_config['seats']:
            seat_id = seat['id']
            status = self.db.get_seat_status(self.store_id, seat_id)
            if status:
                self.previous_occupancy[seat_id] = status.get('status', 'empty')
            else:
                self.previous_occupancy[seat_id] = 'empty'

        print(f"[Channel {self.channel_id}] ✅ Initialized with {len(roi_config['seats'])} seats")
        return True

    def connect_rtsp(self) -> bool:
        """Connect to RTSP stream."""
        print(f"[Channel {self.channel_id}] Connecting to RTSP...")
        if self.rtsp_client.connect(timeout=15):
            print(f"[Channel {self.channel_id}] ✅ RTSP connected")
            return True
        else:
            print(f"[Channel {self.channel_id}] ❌ RTSP connection failed")
            return False

    def process_frame(self, frame):
        """Process a single frame and update seat statuses."""
        # Detect persons
        detections = self.detector.detect_persons(frame)

        # Match with ROIs
        occupancy = self.roi_matcher.check_occupancy(
            detections,
            iou_threshold=settings.IOU_THRESHOLD
        )

        # Process each seat
        current_time = datetime.now()

        for seat_id, info in occupancy.items():
            current_status = info['status']  # 'occupied' or 'empty'
            person_detected = current_status == 'occupied'
            object_detected = False  # TODO: Implement object detection
            confidence = info['max_iou'] if person_detected else 0.0

            # Get previous status
            prev_status = self.previous_occupancy.get(seat_id, 'empty')

            # Determine new status (considering abandoned items)
            new_status = current_status

            # Abandoned item detection logic
            if not person_detected and object_detected:
                # Object without person - increment timer
                self.abandoned_timers[seat_id] += self.snapshot_interval
                if self.abandoned_timers[seat_id] >= 600:  # 10 minutes
                    new_status = 'abandoned'
            else:
                # Reset timer
                self.abandoned_timers[seat_id] = 0

            # Calculate vacant duration
            vacant_duration = 0
            last_person_seen = None
            last_empty_time = None

            if new_status == 'empty':
                # Get previous status from DB to calculate duration
                db_status = self.db.get_seat_status(self.store_id, seat_id)
                if db_status:
                    if db_status.get('last_empty_time'):
                        last_empty_time = db_status['last_empty_time']
                        vacant_duration = int((current_time - last_empty_time).total_seconds())
                    else:
                        last_empty_time = current_time
                else:
                    last_empty_time = current_time
            elif new_status == 'occupied':
                last_person_seen = current_time

            # Update database
            status_update = {
                'status': new_status,
                'person_detected': person_detected,
                'object_detected': object_detected,
                'detection_confidence': confidence,
                'last_person_seen': last_person_seen,
                'last_empty_time': last_empty_time,
                'vacant_duration_seconds': vacant_duration
            }

            try:
                self.db.update_seat_status(self.store_id, seat_id, status_update)
            except Exception as e:
                print(f"[Channel {self.channel_id}] ⚠️  Failed to update status for {seat_id}: {e}")

            # Log event if status changed
            if new_status != prev_status:
                event_type_map = {
                    ('empty', 'occupied'): 'person_enter',
                    ('occupied', 'empty'): 'person_leave',
                    ('empty', 'abandoned'): 'abandoned_detected',
                    ('occupied', 'abandoned'): 'abandoned_detected',
                    ('abandoned', 'occupied'): 'person_enter',
                    ('abandoned', 'empty'): 'item_removed'
                }

                event_type = event_type_map.get((prev_status, new_status), 'status_change')

                # Get bounding box if detected
                bbox = None
                if person_detected and info.get('matched_detection'):
                    det = info['matched_detection']
                    bbox = {
                        'bbox_x1': int(det[0]),
                        'bbox_y1': int(det[1]),
                        'bbox_x2': int(det[2]),
                        'bbox_y2': int(det[3])
                    }

                event_data = {
                    'store_id': self.store_id,
                    'seat_id': seat_id,
                    'channel_id': self.channel_id,
                    'event_type': event_type,
                    'previous_status': prev_status,
                    'new_status': new_status,
                    'person_detected': person_detected,
                    'object_detected': object_detected,
                    'confidence': confidence,
                    **(bbox or {}),
                    'metadata': {
                        'detections_count': len(detections),
                        'iou': info['max_iou']
                    }
                }

                try:
                    self.db.log_detection_event(event_data)
                    print(f"[Channel {self.channel_id}] 📝 {seat_id}: {prev_status} → {new_status}")
                except Exception as e:
                    print(f"[Channel {self.channel_id}] ⚠️  Failed to log event for {seat_id}: {e}")

            # Update previous state
            self.previous_occupancy[seat_id] = new_status

    def run(self):
        """Main worker loop."""
        try:
            # Initialize in worker process
            if not self.initialize():
                print(f"[Channel {self.channel_id}] ❌ Initialization failed")
                return

            # Connect to RTSP
            if not self.connect_rtsp():
                print(f"[Channel {self.channel_id}] ❌ RTSP connection failed")
                return

            print(f"[Channel {self.channel_id}] 🚀 Starting monitoring loop...")

            # Main loop
            frame_count = 0
            error_count = 0
            max_errors = 10

            while not self.stop_event.is_set():
                try:
                    # Capture frame
                    frame = self.rtsp_client.capture_frame()

                    if frame is None:
                        error_count += 1
                        print(f"[Channel {self.channel_id}] ⚠️  Failed to capture frame ({error_count}/{max_errors})")

                        if error_count >= max_errors:
                            print(f"[Channel {self.channel_id}] ❌ Too many errors, reconnecting...")
                            self.rtsp_client.disconnect()
                            time.sleep(5)
                            if not self.connect_rtsp():
                                print(f"[Channel {self.channel_id}] ❌ Reconnection failed, exiting")
                                break
                            error_count = 0

                        time.sleep(1)
                        continue

                    # Reset error count on successful frame
                    error_count = 0
                    frame_count += 1

                    # Process frame
                    self.process_frame(frame)

                    # Log progress
                    if frame_count % 20 == 0:
                        occupied = sum(1 for s in self.previous_occupancy.values() if s == 'occupied')
                        total = len(self.previous_occupancy)
                        print(f"[Channel {self.channel_id}] 📊 Frame {frame_count}: {occupied}/{total} occupied")

                    # Wait for next snapshot
                    time.sleep(self.snapshot_interval)

                except KeyboardInterrupt:
                    break
                except Exception as e:
                    error_count += 1
                    print(f"[Channel {self.channel_id}] ❌ Error: {e}")
                    if error_count >= max_errors:
                        break
                    time.sleep(2)

        finally:
            # Cleanup
            print(f"[Channel {self.channel_id}] 🛑 Shutting down...")
            if self.rtsp_client:
                self.rtsp_client.disconnect()

            # Log system event
            if self.db:
                try:
                    self.db.log_system_event(
                        store_id=self.store_id,
                        log_level='INFO',
                        component=f'channel_{self.channel_id}_worker',
                        message='Worker stopped',
                        metadata={'frame_count': frame_count}
                    )
                except:
                    pass


class MultiChannelWorker:
    """Manager for multiple channel workers."""

    def __init__(self, store_id: str, channel_ids: List[int]):
        """Initialize multi-channel worker.

        Args:
            store_id: Store identifier
            channel_ids: List of channel IDs to monitor
        """
        self.store_id = store_id
        self.channel_ids = channel_ids
        self.processes: List[Process] = []
        self.stop_event = Event()

        # Load store config
        db = get_supabase_client()
        self.store = db.get_store(store_id)
        if not self.store:
            raise ValueError(f"Store {store_id} not found")

    def get_rtsp_url(self, channel_id: int) -> str:
        """Generate RTSP URL for channel."""
        username = settings.RTSP_USERNAME
        password = settings.RTSP_PASSWORD
        host = self.store.get('rtsp_host') or settings.RTSP_HOST
        port = self.store.get('rtsp_port') or settings.RTSP_PORT
        path = f"live_{channel_id:02d}"

        return f"rtsp://{username}:{password}@{host}:{port}/{path}"

    def start(self):
        """Start all channel workers."""
        print(f"\n{'='*60}")
        print(f"Starting Multi-Channel Detection Worker")
        print(f"Store: {self.store['store_name']} ({self.store_id})")
        print(f"Channels: {self.channel_ids}")
        print(f"{'='*60}\n")

        for channel_id in self.channel_ids:
            rtsp_url = self.get_rtsp_url(channel_id)

            worker = ChannelWorker(
                store_id=self.store_id,
                channel_id=channel_id,
                rtsp_url=rtsp_url,
                stop_event=self.stop_event,
                snapshot_interval=settings.SNAPSHOT_INTERVAL
            )

            process = Process(target=worker.run, name=f"Channel-{channel_id}")
            process.start()
            self.processes.append(process)

            print(f"✅ Started worker for channel {channel_id} (PID: {process.pid})")
            time.sleep(1)  # Stagger starts

        print(f"\n🚀 All {len(self.processes)} workers started!\n")

    def stop(self):
        """Stop all workers."""
        print("\n🛑 Stopping all workers...")
        self.stop_event.set()

        for process in self.processes:
            process.join(timeout=10)
            if process.is_alive():
                print(f"⚠️  Force terminating {process.name}")
                process.terminate()
                process.join(timeout=5)

        print("✅ All workers stopped\n")

    def wait(self):
        """Wait for all workers to complete."""
        try:
            for process in self.processes:
                process.join()
        except KeyboardInterrupt:
            print("\n⚠️  Received interrupt signal")
            self.stop()


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Real-time CCTV seat detection worker")
    parser.add_argument(
        '--store',
        type=str,
        default=os.getenv('GOSCA_STORE_ID', '').split('-')[1].lower() if os.getenv('GOSCA_STORE_ID') else 'oryudong',
        help='Store ID (e.g., oryudong, gangnam)'
    )
    parser.add_argument(
        '--channels',
        type=str,
        default=None,
        help='Comma-separated channel IDs (e.g., 1,2,3). Default: all active channels'
    )

    args = parser.parse_args()

    # Parse channels
    if args.channels:
        channel_ids = [int(c.strip()) for c in args.channels.split(',')]
    else:
        channel_ids = settings.ACTIVE_CHANNELS

    # Create and start worker
    worker = MultiChannelWorker(args.store, channel_ids)

    # Handle signals
    def signal_handler(sig, frame):
        print("\n⚠️  Received shutdown signal")
        worker.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Start
    worker.start()

    # Wait
    worker.wait()


if __name__ == "__main__":
    main()
