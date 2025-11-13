# ML Models for Nami Face Recognition

This directory contains the machine learning models used by Nami for face detection and recognition.

## Required Models

### 1. YuNet - Face Detection

**File:** `face_detection_yunet_2023mar.onnx`

**Source:** OpenCV Zoo
- GitHub: https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet
- Direct: https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx

**Size:** ~353 KB

**License:** MIT

**Description:**
- Lightweight face detector optimized for mobile
- Detects faces and 5 facial landmarks
- Fast inference (15-30ms on mobile)

### 2. ArcFace MobileFaceNet - Face Recognition

**File:** `arcface_mobilefacenet.onnx`

**Recommended Sources:**

#### Option A: InsightFace (Recommended for Sailfish OS)
- GitHub: https://github.com/deepinsight/insightface/tree/master/model_zoo
- Model: `buffalo_l` or `buffalo_sc` (smaller)
- Extract recognition model from package

#### Option B: ONNX Model Zoo
- https://github.com/onnx/models/tree/main/vision/body_analysis/arcface
- Note: Full ResNet100 model is large (260MB), consider quantization

#### Option C: Custom MobileFaceNet
Convert from PyTorch/TensorFlow to ONNX:
```python
import torch
import onnx

# Load PyTorch model
model = MobileFaceNet()
model.load_state_dict(torch.load('mobilefacenet.pth'))
model.eval()

# Export to ONNX
dummy_input = torch.randn(1, 3, 112, 112)
torch.onnx.export(model, dummy_input, 'arcface_mobilefacenet.onnx',
                  input_names=['input'],
                  output_names=['output'],
                  dynamic_axes={'input': {0: 'batch_size'},
                               'output': {0: 'batch_size'}})
```

**Expected Input:**
- Shape: [1, 3, 112, 112]
- Format: RGB, normalized to [-1, 1]
- Type: float32

**Output:**
- Shape: [1, 512] (embedding vector)
- Type: float32

**Size:** ~2-5 MB (MobileFaceNet), 260 MB (ResNet100)

**License:** Various (check source)

## Download Models

Run the download script:
```bash
cd python
python3 download_models.py
```

Or download manually and place in this directory.

## Model Performance Targets

### Sailfish OS Devices

**Sony Xperia 10 III (High-end):**
- YuNet: 15-20ms per frame
- ArcFace: 50-80ms per face
- Target: 30+ FPS

**Sony Xperia XA2 (Mid-range):**
- YuNet: 25-35ms per frame
- ArcFace: 80-120ms per face
- Target: 20-30 FPS

**Jolla C (Low-end):**
- YuNet: 40-60ms per frame
- ArcFace: 150-200ms per face
- Target: 10-15 FPS (degraded mode)

## Model Optimization

### Quantization (INT8)
Reduce model size and improve inference speed:
```python
import onnx
from onnxruntime.quantization import quantize_dynamic

model_fp32 = 'arcface_mobilefacenet.onnx'
model_quant = 'arcface_mobilefacenet_int8.onnx'

quantize_dynamic(model_fp32, model_quant, weight_type='int8')
```

Expected improvements:
- Size: 70-75% reduction
- Speed: 2-4x faster on CPU
- Accuracy: < 1% loss

## Troubleshooting

### Model not loading
- Check file exists in `python/models/`
- Verify ONNX format (use `onnx.checker.check_model()`)
- Ensure ONNX Runtime is installed

### Poor performance
- Enable quantization
- Reduce input resolution
- Use GPU acceleration if available
- Check CPU frequency (thermal throttling)

### Low accuracy
- Verify model input preprocessing
- Check embedding normalization (L2)
- Adjust recognition threshold
- Use full ResNet100 model instead of MobileFaceNet

## Privacy & Security

**All models run 100% on-device:**
- ✓ No data sent to external servers
- ✓ No cloud processing
- ✓ No telemetry
- ✓ GDPR compliant by design

**Model files are:**
- Public pre-trained models
- Not specific to any individual
- Cannot reverse engineer to training data
- Safe to distribute with application
