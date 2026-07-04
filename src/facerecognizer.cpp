#include "facerecognizer.h"
#include <QDebug>
#include "logging.h"
#include <cmath>

FaceRecognizer::FaceRecognizer(QObject *parent)
    : QObject(parent)
    , m_modelLoaded(false)
{
}

FaceRecognizer::~FaceRecognizer()
{
}

bool FaceRecognizer::loadModel(const QString &modelPath)
{
    try {
        qCDebug(lcNami) << "Loading SFace recognition model from:" << modelPath;

        m_recognizer = cv::FaceRecognizerSF::create(
            modelPath.toStdString(),
            "",
            cv::dnn::DNN_BACKEND_OPENCV,
            cv::dnn::DNN_TARGET_CPU
        );

        if (m_recognizer.empty()) {
            emit error("Failed to create SFace recognizer");
            return false;
        }

        m_modelLoaded = true;
        qCDebug(lcNami) << "SFace model loaded successfully (112x112 input, 128-d output)";

        return true;
    }
    catch (const cv::Exception &e) {
        QString errorMsg = QString("OpenCV exception loading recognition model: %1").arg(e.what());
        qWarning() << errorMsg;
        emit error(errorMsg);
        return false;
    }
}

FaceEmbedding FaceRecognizer::extractEmbedding(const cv::Mat &image, const FaceDetection &detection)
{
    if (!m_modelLoaded) {
        emit error("Model not loaded");
        return FaceEmbedding();
    }

    if (image.empty()) {
        emit error("Empty input image");
        return FaceEmbedding();
    }

    // alignCrop needs the 5 landmarks; without them the warp is garbage
    if (detection.landmarks.size() != 5) {
        qWarning() << "Face detection has" << detection.landmarks.size()
                   << "landmarks, expected 5 - skipping";
        return FaceEmbedding();
    }

    try {
        cv::Mat faceRow = detectionToFaceRow(image, detection);

        // alignCrop warps to the 112x112 ArcFace template using the 5
        // landmarks; feature applies the model's own preprocessing
        cv::Mat aligned;
        m_recognizer->alignCrop(image, faceRow, aligned);

        cv::Mat feature;
        m_recognizer->feature(aligned, feature);

        FaceEmbedding embedding(feature.ptr<float>(0),
                                feature.ptr<float>(0) + feature.cols);

        return normalizeEmbedding(embedding);
    }
    catch (const cv::Exception &e) {
        QString errorMsg = QString("OpenCV exception during embedding extraction: %1").arg(e.what());
        qWarning() << errorMsg;
        emit error(errorMsg);
        return FaceEmbedding();
    }
}

cv::Mat FaceRecognizer::detectionToFaceRow(const cv::Mat &image, const FaceDetection &detection)
{
    // YuNet row format: [x, y, w, h, re_x, re_y, le_x, le_y, nose_x, nose_y,
    // rcm_x, rcm_y, lcm_x, lcm_y, score] in pixels; alignCrop reads the
    // landmarks at columns 4-13
    cv::Mat faceRow(1, 15, CV_32F, cv::Scalar(0));

    faceRow.at<float>(0, 0) = static_cast<float>(detection.bbox.x() * image.cols);
    faceRow.at<float>(0, 1) = static_cast<float>(detection.bbox.y() * image.rows);
    faceRow.at<float>(0, 2) = static_cast<float>(detection.bbox.width() * image.cols);
    faceRow.at<float>(0, 3) = static_cast<float>(detection.bbox.height() * image.rows);

    for (int i = 0; i < detection.landmarks.size() && i < 5; i++) {
        faceRow.at<float>(0, 4 + i * 2) = static_cast<float>(detection.landmarks[i].x() * image.cols);
        faceRow.at<float>(0, 5 + i * 2) = static_cast<float>(detection.landmarks[i].y() * image.rows);
    }

    faceRow.at<float>(0, 14) = detection.confidence;

    return faceRow;
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
