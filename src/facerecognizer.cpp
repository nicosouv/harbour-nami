#include "facerecognizer.h"
#include <QDebug>
#include <cmath>

FaceRecognizer::FaceRecognizer(QObject *parent)
    : QObject(parent)
    , m_env(ORT_LOGGING_LEVEL_WARNING, "FaceRecognizer")
    , m_session(nullptr)
    , m_modelLoaded(false)
{
    // Configure session options for CPU (ARM optimization)
    m_sessionOptions.SetIntraOpNumThreads(2);  // 2 threads for mobile
    m_sessionOptions.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
}

FaceRecognizer::~FaceRecognizer()
{
    if (m_session) {
        delete m_session;
    }
}

bool FaceRecognizer::loadModel(const QString &modelPath)
{
    try {
        qDebug() << "Loading ArcFace recognition model from:" << modelPath;

        // Create ONNX Runtime session
        m_session = new Ort::Session(m_env, modelPath.toStdWString().c_str(), m_sessionOptions);

        // Get input/output info
        Ort::AllocatorWithDefaultOptions allocator;

        // Input
        size_t numInputNodes = m_session->GetInputCount();
        if (numInputNodes != 1) {
            emit error(QString("Expected 1 input, got %1").arg(numInputNodes));
            return false;
        }

        m_inputNames.push_back(m_session->GetInputNameAllocated(0, allocator).get());

        Ort::TypeInfo inputTypeInfo = m_session->GetInputTypeInfo(0);
        auto tensorInfo = inputTypeInfo.GetTensorTypeAndShapeInfo();
        m_inputShape = tensorInfo.GetShape();

        qDebug() << "Input shape:" << m_inputShape[0] << m_inputShape[1]
                 << m_inputShape[2] << m_inputShape[3];

        // Output
        size_t numOutputNodes = m_session->GetOutputCount();
        if (numOutputNodes != 1) {
            emit error(QString("Expected 1 output, got %1").arg(numOutputNodes));
            return false;
        }

        m_outputNames.push_back(m_session->GetOutputNameAllocated(0, allocator).get());

        Ort::TypeInfo outputTypeInfo = m_session->GetOutputTypeInfo(0);
        auto outputTensorInfo = outputTypeInfo.GetTensorTypeAndShapeInfo();
        m_outputShape = outputTensorInfo.GetShape();

        qDebug() << "Output shape:" << m_outputShape[0] << m_outputShape[1];

        m_modelLoaded = true;
        qDebug() << "ArcFace model loaded successfully";
        qDebug() << "Expected input: 112x112 RGB, normalized";
        qDebug() << "Output: 512-d embedding vector";

        return true;
    }
    catch (const Ort::Exception &e) {
        QString errorMsg = QString("ONNX Runtime exception loading model: %1").arg(e.what());
        qWarning() << errorMsg;
        emit error(errorMsg);
        return false;
    }
}

FaceEmbedding FaceRecognizer::extractEmbedding(const QImage &faceImage)
{
    cv::Mat mat = qImageToCvMat(faceImage);
    return extractEmbedding(mat);
}

FaceEmbedding FaceRecognizer::extractEmbedding(const cv::Mat &faceImage)
{
    if (!m_modelLoaded) {
        emit error("Model not loaded");
        return FaceEmbedding();
    }

    if (faceImage.empty()) {
        emit error("Empty face image");
        return FaceEmbedding();
    }

    try {
        // Preprocess image
        std::vector<float> inputTensor = preprocessImage(faceImage);

        // Create input tensor
        size_t inputTensorSize = inputTensor.size();
        Ort::MemoryInfo memoryInfo = Ort::MemoryInfo::CreateCpu(
            OrtAllocatorType::OrtArenaAllocator, OrtMemType::OrtMemTypeDefault);

        Ort::Value inputOrtTensor = Ort::Value::CreateTensor<float>(
            memoryInfo,
            inputTensor.data(),
            inputTensorSize,
            m_inputShape.data(),
            m_inputShape.size()
        );

        // Run inference
        std::vector<Ort::Value> outputTensors = m_session->Run(
            Ort::RunOptions{nullptr},
            m_inputNames.data(),
            &inputOrtTensor,
            1,
            m_outputNames.data(),
            1
        );

        // Get output
        float* outputData = outputTensors[0].GetTensorMutableData<float>();
        size_t outputSize = m_outputShape[1];  // Should be 512

        FaceEmbedding embedding(outputData, outputData + outputSize);

        // L2 normalize
        embedding = normalizeEmbedding(embedding);

        qDebug() << "Extracted" << embedding.size() << "dimensional embedding";

        return embedding;
    }
    catch (const Ort::Exception &e) {
        QString errorMsg = QString("ONNX Runtime exception during inference: %1").arg(e.what());
        qWarning() << errorMsg;
        emit error(errorMsg);
        return FaceEmbedding();
    }
}

float FaceRecognizer::computeSimilarity(const FaceEmbedding &emb1, const FaceEmbedding &emb2)
{
    if (emb1.size() != emb2.size() || emb1.empty()) {
        qWarning() << "Invalid embeddings for similarity computation";
        return 0.0f;
    }

    // Cosine similarity (dot product of normalized vectors)
    float dotProduct = 0.0f;
    for (size_t i = 0; i < emb1.size(); i++) {
        dotProduct += emb1[i] * emb2[i];
    }

    // Convert from [-1, 1] to [0, 1]
    float similarity = (dotProduct + 1.0f) / 2.0f;

    return similarity;
}

FaceMatch FaceRecognizer::matchFace(const FaceEmbedding &faceEmbedding,
                                    const QVector<QPair<int, FaceEmbedding>> &databaseEmbeddings,
                                    float threshold)
{
    FaceMatch bestMatch{-1, 0.0f};

    for (const auto &pair : databaseEmbeddings) {
        int personId = pair.first;
        const FaceEmbedding &dbEmbedding = pair.second;

        float similarity = computeSimilarity(faceEmbedding, dbEmbedding);

        if (similarity > bestMatch.similarity) {
            bestMatch.personId = personId;
            bestMatch.similarity = similarity;
        }
    }

    // Check threshold
    if (bestMatch.similarity < threshold) {
        return FaceMatch{-1, bestMatch.similarity};
    }

    return bestMatch;
}

FaceEmbedding FaceRecognizer::normalizeEmbedding(const FaceEmbedding &embedding)
{
    // L2 normalization
    float norm = 0.0f;
    for (float val : embedding) {
        norm += val * val;
    }
    norm = std::sqrt(norm);

    if (norm == 0.0f) {
        return embedding;
    }

    FaceEmbedding normalized(embedding.size());
    for (size_t i = 0; i < embedding.size(); i++) {
        normalized[i] = embedding[i] / norm;
    }

    return normalized;
}

cv::Mat FaceRecognizer::qImageToCvMat(const QImage &image)
{
    QImage rgb = image.convertToFormat(QImage::Format_RGB888);
    cv::Mat mat(rgb.height(), rgb.width(), CV_8UC3,
                const_cast<uchar*>(rgb.bits()), rgb.bytesPerLine());
    return mat.clone();
}

std::vector<float> FaceRecognizer::preprocessImage(const cv::Mat &faceImage)
{
    // Resize to 112x112
    cv::Mat resized;
    cv::resize(faceImage, resized, cv::Size(112, 112));

    // Convert to RGB if needed
    cv::Mat rgb;
    if (resized.channels() == 3) {
        cv::cvtColor(resized, rgb, cv::COLOR_BGR2RGB);
    } else {
        rgb = resized;
    }

    // ArcFace preprocessing: (pixel - 127.5) / 128.0
    // Input format: NHWC [1, 112, 112, 3]
    std::vector<float> inputTensor;
    inputTensor.reserve(1 * 112 * 112 * 3);

    for (int h = 0; h < 112; h++) {
        for (int w = 0; w < 112; w++) {
            cv::Vec3b pixel = rgb.at<cv::Vec3b>(h, w);
            for (int c = 0; c < 3; c++) {
                float normalized = (static_cast<float>(pixel[c]) - 127.5f) / 128.0f;
                inputTensor.push_back(normalized);
            }
        }
    }

    return inputTensor;
}
