# ArcFace Model Download Instructions

The ArcFace MobileFaceNet model is required for face recognition but cannot be automatically bundled due to licensing/hosting constraints.

## Quick Setup

### Option 1: InsightFace (Recommended)

Download from InsightFace model zoo:

```bash
# Clone InsightFace repo
git clone https://github.com/deepinsight/insightface.git
cd insightface

# Navigate to model zoo
cd model_zoo

# Download buffalo_sc (small, for mobile)
# Or buffalo_l (larger, more accurate)

# Extract the recognition model and convert to ONNX if needed
# The file should be named: arcface_mobilefacenet.onnx
```

### Option 2: Pre-converted ONNX Model

If you have access to a pre-converted MobileFaceNet ONNX model:

```bash
# Copy to models directory
cp /path/to/your/arcface_mobilefacenet.onnx python/models/
```

### Option 3: Convert from PyTorch

If you have PyTorch weights:

```python
import torch
import onnx
from your_model import MobileFaceNet

# Load model
model = MobileFaceNet()
model.load_state_dict(torch.load('mobilefacenet.pth'))
model.eval()

# Export to ONNX
dummy_input = torch.randn(1, 3, 112, 112)
torch.onnx.export(
    model,
    dummy_input,
    'arcface_mobilefacenet.onnx',
    input_names=['input'],
    output_names=['output'],
    opset_version=11
)
```

## Model Specifications

**Required:**
- **Format:** ONNX
- **Input shape:** [1, 3, 112, 112] (NCHW format)
- **Input type:** float32, normalized to [-1, 1]
- **Output shape:** [1, 512] (embedding vector)
- **Output type:** float32

**Recommended:**
- **Model:** MobileFaceNet or ArcFace-MobileFaceNet
- **Size:** 2-5 MB (MobileFaceNet), avoid ResNet100 (260MB)
- **Quantization:** INT8 quantized version preferred for mobile

## Verification

After placing the model, verify it:

```bash
python3 python/download_models.py
```

Or in Python:

```python
import onnx

model = onnx.load('python/models/arcface_mobilefacenet.onnx')
onnx.checker.check_model(model)

print("Input:", model.graph.input[0].name,
      [d.dim_value for d in model.graph.input[0].type.tensor_type.shape.dim])
print("Output:", model.graph.output[0].name,
      [d.dim_value for d in model.graph.output[0].type.tensor_type.shape.dim])
```

Expected output:
```
Input: input [1, 3, 112, 112]
Output: output [1, 512]
```

## Alternative: Bundle with App

For Harbour Store distribution, consider:

1. **Host on GitHub Releases:**
   ```bash
   # Upload model as release asset
   gh release create v0.1.0 python/models/arcface_mobilefacenet.onnx
   ```

2. **Download in CI/CD:**
   ```yaml
   - name: Download ArcFace Model
     run: |
       curl -L "https://github.com/nicosouv/harbour-nami/releases/download/v0.1.0/arcface_mobilefacenet.onnx" \
         -o python/models/arcface_mobilefacenet.onnx
   ```

3. **Bundle in RPM:**
   - Model will be included in package
   - Installed to `/usr/share/harbour-nami/python/models/`
   - App works immediately after installation

## Troubleshooting

### Model not loading
- Check file exists: `ls -lh python/models/arcface_mobilefacenet.onnx`
- Verify ONNX format: `python3 -c "import onnx; onnx.checker.check_model(onnx.load('python/models/arcface_mobilefacenet.onnx'))"`
- Check size: Should be 2-5 MB for MobileFaceNet

### Wrong input/output shape
- Verify shape matches [1,3,112,112] → [1,512]
- May need to convert or re-export model

### Poor recognition accuracy
- Ensure model is pre-trained on face recognition task
- Check preprocessing (normalize to [-1,1], RGB format)
- Consider using larger model (ArcFace ResNet50 instead of MobileFaceNet)

## License Compliance

Ensure your ArcFace model complies with:
- Original model license
- InsightFace license (if using their models)
- Your app distribution requirements

Most face recognition models are released under permissive licenses (Apache 2.0, MIT) but verify before bundling.
