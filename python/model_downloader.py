#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Automatic model downloader for Nami
Downloads ML models on first app launch if missing
"""

import os
import urllib.request
import hashlib
from pathlib import Path


class ModelDownloader:
    """Download and verify ML models"""

    def __init__(self, models_dir=None):
        """Initialize downloader"""
        if models_dir is None:
            models_dir = Path(__file__).parent / "models"

        self.models_dir = Path(models_dir)
        self.models_dir.mkdir(parents=True, exist_ok=True)

    def check_models_available(self):
        """
        Check if all required models are available

        Returns:
            dict: Status of each model
        """
        yunet_path = self.models_dir / "face_detection_yunet_2023mar.onnx"
        arcface_path = self.models_dir / "arcface_mobilefacenet.onnx"

        return {
            'yunet': yunet_path.exists(),
            'arcface': arcface_path.exists(),
            'all_ready': yunet_path.exists() and arcface_path.exists()
        }

    def download_yunet(self, progress_callback=None):
        """
        Download YuNet face detection model

        Args:
            progress_callback: Optional callback(current, total, percentage)

        Returns:
            bool: Success
        """
        url = "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
        dest_path = self.models_dir / "face_detection_yunet_2023mar.onnx"

        if dest_path.exists():
            return True

        try:
            def progress_hook(count, block_size, total_size):
                if progress_callback and total_size > 0:
                    current = count * block_size
                    percentage = min(100, int(current * 100 / total_size))
                    progress_callback(current, total_size, percentage)

            urllib.request.urlretrieve(url, str(dest_path), progress_hook)

            # Verify file size (should be ~353KB)
            file_size = os.path.getsize(dest_path)
            if file_size < 300000:  # Less than 300KB is suspicious
                os.remove(dest_path)
                return False

            return True

        except Exception as e:
            print(f"Failed to download YuNet: {e}")
            if dest_path.exists():
                os.remove(dest_path)
            return False

    def download_arcface(self, progress_callback=None):
        """
        Download ArcFace recognition model

        Note: This is a placeholder. ArcFace models need to be:
        1. Hosted somewhere accessible
        2. Or bundled with the app
        3. Or user provides their own

        Args:
            progress_callback: Optional callback(current, total, percentage)

        Returns:
            bool: Success
        """
        # TODO: Host ArcFace model or bundle with app
        # For now, return False and user must provide model manually

        dest_path = self.models_dir / "arcface_mobilefacenet.onnx"

        if dest_path.exists():
            return True

        # Option 1: Download from user-provided URL (if we host it)
        # url = "https://example.com/models/arcface_mobilefacenet.onnx"

        # Option 2: Bundle with app (preferred for Harbour Store)
        # Model should be in RPM package

        # For now, model must be provided manually
        return False

    def download_all_models(self, progress_callback=None):
        """
        Download all required models

        Args:
            progress_callback: Optional callback(model_name, current, total, percentage)

        Returns:
            dict: Download status for each model
        """
        results = {}

        # Download YuNet
        def yunet_progress(current, total, percentage):
            if progress_callback:
                progress_callback('yunet', current, total, percentage)

        results['yunet'] = self.download_yunet(yunet_progress)

        # Download ArcFace
        def arcface_progress(current, total, percentage):
            if progress_callback:
                progress_callback('arcface', current, total, percentage)

        results['arcface'] = self.download_arcface(arcface_progress)

        results['all_success'] = all(results.values())

        return results

    def get_model_info(self):
        """
        Get information about models

        Returns:
            dict: Model information
        """
        yunet_path = self.models_dir / "face_detection_yunet_2023mar.onnx"
        arcface_path = self.models_dir / "arcface_mobilefacenet.onnx"

        info = {
            'yunet': {
                'name': 'YuNet Face Detection',
                'path': str(yunet_path),
                'exists': yunet_path.exists(),
                'size_mb': round(yunet_path.stat().st_size / 1024 / 1024, 2) if yunet_path.exists() else 0,
                'expected_size_mb': 0.35,
                'url': 'https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet'
            },
            'arcface': {
                'name': 'ArcFace Recognition',
                'path': str(arcface_path),
                'exists': arcface_path.exists(),
                'size_mb': round(arcface_path.stat().st_size / 1024 / 1024, 2) if arcface_path.exists() else 0,
                'expected_size_mb': 2.5,
                'url': 'Manual installation required'
            }
        }

        return info


# Expose functions for PyOtherSide
_downloader = None

def get_downloader():
    """Get or create downloader instance"""
    global _downloader
    if _downloader is None:
        _downloader = ModelDownloader()
    return _downloader

def check_models():
    """Check if models are available"""
    return get_downloader().check_models_available()

def download_models(progress_callback=None):
    """Download all models"""
    return get_downloader().download_all_models(progress_callback)

def get_model_info():
    """Get model information"""
    return get_downloader().get_model_info()


if __name__ == "__main__":
    # Test downloader
    downloader = ModelDownloader()

    print("Checking models...")
    status = downloader.check_models_available()
    print(f"Models available: {status}")

    print("\nModel info:")
    info = downloader.get_model_info()
    for model, data in info.items():
        print(f"\n{data['name']}:")
        print(f"  Exists: {data['exists']}")
        print(f"  Size: {data['size_mb']} MB")
        print(f"  Path: {data['path']}")
