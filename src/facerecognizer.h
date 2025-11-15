#ifndef FACERECOGNIZER_H
#define FACERECOGNIZER_H

#include <QObject>
#include <QString>
#include <QVector>
#include <QImage>
#include <opencv2/opencv.hpp>
#include <onnxruntime_cxx_api.h>

/**
 * @brief Face embedding (512-d vector for ArcFace)
 */
using FaceEmbedding = std::vector<float>;

/**
 * @brief Match result
 */
struct FaceMatch {
    int personId;
    float similarity;  // 0.0 - 1.0
};

/**
 * @brief ArcFace-based face recognition using ONNX Runtime
 *
 * Extracts 512-dimensional embeddings for face matching.
 * Uses cosine similarity for comparison.
 */
class FaceRecognizer : public QObject
{
    Q_OBJECT

public:
    explicit FaceRecognizer(QObject *parent = nullptr);
    ~FaceRecognizer();

    /**
     * @brief Load the ArcFace ONNX model
     * @param modelPath Path to arcface_mobilefacenet.onnx
     * @return true if loaded successfully
     */
    bool loadModel(const QString &modelPath);

    /**
     * @brief Extract face embedding from aligned face image
     * @param faceImage Face image (should be aligned, 112x112 recommended)
     * @return 512-d embedding vector (L2-normalized)
     */
    FaceEmbedding extractEmbedding(const QImage &faceImage);
    FaceEmbedding extractEmbedding(const cv::Mat &faceImage);

    /**
     * @brief Compute cosine similarity between two embeddings
     * @param emb1 First embedding
     * @param emb2 Second embedding
     * @return Similarity score (0.0 - 1.0, higher = more similar)
     */
    static float computeSimilarity(const FaceEmbedding &emb1, const FaceEmbedding &emb2);

    /**
     * @brief Match face against database of embeddings
     * @param faceEmbedding Embedding to match
     * @param databaseEmbeddings Database of (personId, embedding) pairs
     * @param threshold Minimum similarity threshold (default: 0.6)
     * @return Best match or {-1, 0.0} if no match
     */
    static FaceMatch matchFace(const FaceEmbedding &faceEmbedding,
                               const QVector<QPair<int, FaceEmbedding>> &databaseEmbeddings,
                               float threshold = 0.6f);

    /**
     * @brief Normalize embedding to unit vector (L2 normalization)
     */
    static FaceEmbedding normalizeEmbedding(const FaceEmbedding &embedding);

    /**
     * @brief Check if model is loaded
     */
    bool isLoaded() const { return m_modelLoaded; }

    /**
     * @brief Get expected input size
     */
    QSize inputSize() const { return QSize(112, 112); }

signals:
    void error(const QString &message);

private:
    Ort::Env m_env;
    Ort::Session *m_session;
    Ort::SessionOptions m_sessionOptions;
    bool m_modelLoaded;

    std::vector<std::string> m_inputNames;
    std::vector<std::string> m_outputNames;
    std::vector<int64_t> m_inputShape;
    std::vector<int64_t> m_outputShape;

    // Helper: Convert QImage to cv::Mat
    cv::Mat qImageToCvMat(const QImage &image);

    // Helper: Preprocess face image for ArcFace
    // Normalize: (pixel - 127.5) / 128.0
    std::vector<float> preprocessImage(const cv::Mat &faceImage);
};

#endif // FACERECOGNIZER_H
