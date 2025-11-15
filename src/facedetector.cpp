#include "facedetector.h"
#include <QDebug>

FaceDetector::FaceDetector(QObject *parent)
    : QObject(parent)
    , m_modelLoaded(false)
    , m_inputSize(320, 320)  // Default YuNet input size
{
}

FaceDetector::~FaceDetector()
{
}

bool FaceDetector::loadModel(const QString &modelPath)
{
    try {
        qDebug() << "Loading YuNet face detection model from:" << modelPath;

        // Create FaceDetectorYN with OpenCV API
        // Parameters: model_path, config_path, input_size, score_threshold, nms_threshold, top_k, backend_id, target_id
        m_detector = cv::FaceDetectorYN::create(
            modelPath.toStdString(),  // model path
            "",                        // config path (empty for ONNX)
            cv::Size(m_inputSize.width(), m_inputSize.height()),  // input size
            0.3f,                      // score threshold (will be overridden in detect())
            0.3f,                      // NMS threshold
            5000,                      // top_k
            cv::dnn::DNN_BACKEND_OPENCV,   // backend
            cv::dnn::DNN_TARGET_CPU        // target
        );

        if (m_detector.empty()) {
            emit error("Failed to create YuNet detector");
            return false;
        }

        m_modelLoaded = true;
        qDebug() << "YuNet model loaded successfully";
        qDebug() << "Input size:" << m_inputSize.width() << "x" << m_inputSize.height();

        return true;
    }
    catch (const cv::Exception &e) {
        QString errorMsg = QString("OpenCV exception loading model: %1").arg(e.what());
        qWarning() << errorMsg;
        emit error(errorMsg);
        return false;
    }
}

QVector<FaceDetection> FaceDetector::detect(const QImage &image, float confidenceThreshold)
{
    qDebug() << "QImage detection requested - size:" << image.width() << "x" << image.height();
    cv::Mat mat = qImageToCvMat(image);
    qDebug() << "Converted to cv::Mat - size:" << mat.cols << "x" << mat.rows;
    return detect(mat, confidenceThreshold);
}

QVector<FaceDetection> FaceDetector::detect(const cv::Mat &image, float confidenceThreshold)
{
    if (!m_modelLoaded) {
        emit error("Model not loaded");
        return QVector<FaceDetection>();
    }

    if (image.empty()) {
        emit error("Empty input image");
        return QVector<FaceDetection>();
    }

    qDebug() << "=== Face Detection Start ===";
    qDebug() << "Input image size:" << image.cols << "x" << image.rows << "channels:" << image.channels();
    qDebug() << "Confidence threshold:" << confidenceThreshold;

    try {
        // Set input size to match the actual image
        m_detector->setInputSize(cv::Size(image.cols, image.rows));

        // Set score threshold
        m_detector->setScoreThreshold(confidenceThreshold);

        // Detect faces
        cv::Mat faces;
        qDebug() << "Running YuNet detector...";
        m_detector->detect(image, faces);

        qDebug() << "Detection complete - faces matrix: rows=" << faces.rows << "cols=" << faces.cols << "type=" << faces.type();

        // Convert results
        QVector<FaceDetection> detections;

        if (faces.rows > 0) {
            qDebug() << "Found" << faces.rows << "faces";

            for (int i = 0; i < faces.rows; i++) {
                FaceDetection detection;

                // YuNet output format per row: [x, y, w, h, x_re, y_re, x_le, y_le, x_nt, y_nt, x_rcm, y_rcm, x_lcm, y_lcm, score]
                // Coordinates are in pixels

                float x = faces.at<float>(i, 0);
                float y = faces.at<float>(i, 1);
                float w = faces.at<float>(i, 2);
                float h = faces.at<float>(i, 3);
                float score = faces.at<float>(i, 14);

                qDebug() << "  Face" << i << "- bbox (pixels):" << x << y << w << h << "score:" << score;

                // Normalize to [0-1]
                detection.bbox = QRectF(
                    x / image.cols,
                    y / image.rows,
                    w / image.cols,
                    h / image.rows
                );
                detection.confidence = score;

                // Extract 5 landmarks and normalize
                for (int j = 0; j < 5; j++) {
                    float lx = faces.at<float>(i, 4 + j*2) / image.cols;
                    float ly = faces.at<float>(i, 5 + j*2) / image.rows;
                    detection.landmarks.append(QPointF(lx, ly));
                }

                detections.append(detection);
            }
        } else {
            qDebug() << "No faces detected";
        }

        qDebug() << "=== Detection Complete: Found" << detections.size() << "faces ===";

        return detections;
    }
    catch (const cv::Exception &e) {
        QString errorMsg = QString("OpenCV exception during detection: %1").arg(e.what());
        qWarning() << errorMsg;
        emit error(errorMsg);
        return QVector<FaceDetection>();
    }
}

cv::Mat FaceDetector::qImageToCvMat(const QImage &image)
{
    // Convert QImage to cv::Mat
    QImage rgb = image.convertToFormat(QImage::Format_RGB888);
    cv::Mat mat(rgb.height(), rgb.width(), CV_8UC3,
                const_cast<uchar*>(rgb.bits()), rgb.bytesPerLine());

    // Clone to ensure data persistence
    return mat.clone();
}
