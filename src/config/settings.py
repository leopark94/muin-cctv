"""Configuration settings for the CCTV seat detection system."""
import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

class Settings:
    """Application settings."""

    # Project paths
    BASE_DIR = Path(__file__).parent.parent.parent
    DATA_DIR = BASE_DIR / "data"
    ROI_CONFIG_DIR = DATA_DIR / "roi_configs"
    SNAPSHOT_DIR = DATA_DIR / "snapshots"
    LOG_DIR = BASE_DIR / "logs"

    # RTSP settings
    RTSP_USERNAME = os.getenv("RTSP_USERNAME", "admin")
    RTSP_PASSWORD = os.getenv("RTSP_PASSWORD", "")
    RTSP_HOST = os.getenv("RTSP_HOST", "218.50.241.157")
    RTSP_PORT = os.getenv("RTSP_PORT", "8554")
    RTSP_PATH = os.getenv("RTSP_PATH", "live_12")

    # Active channels (comma-separated string, e.g., "1,2,3,12")
    ACTIVE_CHANNELS_STR = os.getenv("ACTIVE_CHANNELS", "")

    @property
    def ACTIVE_CHANNELS(self):
        """Get list of active channel numbers from env variable."""
        if not self.ACTIVE_CHANNELS_STR:
            # If not set, use all 16 channels
            return list(range(1, 17))
        try:
            channels = [int(ch.strip()) for ch in self.ACTIVE_CHANNELS_STR.split(",")]
            return sorted([ch for ch in channels if 1 <= ch <= 16])
        except:
            # If parsing fails, use all channels
            return list(range(1, 17))

    # Model settings
    YOLO_MODEL = os.getenv("YOLO_MODEL", "yolov8n.pt")
    CONFIDENCE_THRESHOLD = float(os.getenv("CONFIDENCE_THRESHOLD", "0.5"))
    IOU_THRESHOLD = float(os.getenv("IOU_THRESHOLD", "0.3"))

    # Processing settings
    SNAPSHOT_INTERVAL = int(os.getenv("SNAPSHOT_INTERVAL", "3"))
    MAX_WORKERS = int(os.getenv("MAX_WORKERS", "4"))

    # API settings
    API_HOST = os.getenv("API_HOST", "0.0.0.0")
    API_PORT = int(os.getenv("API_PORT", "8000"))

    def get_rtsp_url(self, path: str = None) -> str:
        """Generate RTSP URL.

        Args:
            path: RTSP path (e.g., 'live_12', 'ch1'). If None, uses RTSP_PATH from env.

        Returns:
            Complete RTSP URL
        """
        if path is None:
            path = self.RTSP_PATH
        return f"rtsp://{self.RTSP_USERNAME}:{self.RTSP_PASSWORD}@{self.RTSP_HOST}:{self.RTSP_PORT}/{path}"

    def ensure_directories(self):
        """Create necessary directories if they don't exist."""
        self.ROI_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self.SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
        self.LOG_DIR.mkdir(parents=True, exist_ok=True)


settings = Settings()
settings.ensure_directories()
