"""Configuration settings for the CCTV seat detection system."""
import os
from pathlib import Path
from typing import List, Optional
from dotenv import load_dotenv

# Load environment variables
load_dotenv()


class StoreConfig:
    """Store-specific configuration."""

    def __init__(self, store_id: str):
        """Initialize store configuration.

        Args:
            store_id: Store identifier (e.g., 'oryudong', 'gangnam')
        """
        self.store_id = store_id
        self._prefix = store_id.upper()

    def _get_env(self, key: str, default: str = "") -> str:
        """Get environment variable with store-specific fallback.

        First tries {STORE_ID}_{KEY}, then falls back to {KEY}.
        """
        store_specific = os.getenv(f"{self._prefix}_{key}")
        if store_specific is not None:
            return store_specific
        return os.getenv(key, default)

    @property
    def rtsp_host(self) -> str:
        return self._get_env("RTSP_HOST", "localhost")

    @property
    def rtsp_port(self) -> str:
        return self._get_env("RTSP_PORT", "8554")

    @property
    def rtsp_username(self) -> str:
        return self._get_env("RTSP_USERNAME", "admin")

    @property
    def rtsp_password(self) -> str:
        return self._get_env("RTSP_PASSWORD", "")

    @property
    def active_channels(self) -> List[int]:
        """Get list of active channel numbers."""
        channels_str = self._get_env("ACTIVE_CHANNELS", "")
        if not channels_str:
            return list(range(1, 17))  # Default: all 16 channels
        try:
            channels = [int(ch.strip()) for ch in channels_str.split(",")]
            return sorted([ch for ch in channels if 1 <= ch <= 16])
        except ValueError:
            return list(range(1, 17))

    def get_rtsp_url(self, channel_id: int) -> str:
        """Generate RTSP URL for a specific channel."""
        path = f"live_{channel_id:02d}"
        return f"rtsp://{self.rtsp_username}:{self.rtsp_password}@{self.rtsp_host}:{self.rtsp_port}/{path}"

    def __repr__(self) -> str:
        return (
            f"StoreConfig(store_id='{self.store_id}', "
            f"rtsp_host='{self.rtsp_host}', "
            f"channels={self.active_channels})"
        )


class Settings:
    """Application settings."""

    # Project paths
    BASE_DIR = Path(__file__).parent.parent.parent
    DATA_DIR = BASE_DIR / "data"
    ROI_CONFIG_DIR = DATA_DIR / "roi_configs"
    SNAPSHOT_DIR = DATA_DIR / "snapshots"
    LOG_DIR = BASE_DIR / "logs"

    # Current store (from STORE_ID env variable)
    STORE_ID = os.getenv("STORE_ID", "oryudong")

    # RTSP settings (backward compatibility - use StoreConfig for multi-store)
    RTSP_USERNAME = os.getenv("RTSP_USERNAME", "admin")
    RTSP_PASSWORD = os.getenv("RTSP_PASSWORD", "")
    RTSP_HOST = os.getenv("RTSP_HOST", "localhost")
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

    # GoSca 좌석 관리 시스템 설정
    GOSCA_BASE_URL = os.getenv("GOSCA_BASE_URL", "https://gosca.co.kr")
    GOSCA_STORE_ID = os.getenv("GOSCA_STORE_ID", "Anding-Oryudongyeok-sca")

    # Debug settings
    DEBUG = os.getenv("DEBUG", "false").lower() in ("true", "1", "yes")
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
    DRY_RUN = os.getenv("DRY_RUN", "false").lower() in ("true", "1", "yes")

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

    def get_store_config(self, store_id: Optional[str] = None) -> StoreConfig:
        """Get store-specific configuration.

        Args:
            store_id: Store identifier. If None, uses STORE_ID from env.

        Returns:
            StoreConfig instance with store-specific settings
        """
        if store_id is None:
            store_id = self.STORE_ID
        return StoreConfig(store_id)

    def ensure_directories(self):
        """Create necessary directories if they don't exist."""
        self.ROI_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self.SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
        self.LOG_DIR.mkdir(parents=True, exist_ok=True)


settings = Settings()
settings.ensure_directories()
