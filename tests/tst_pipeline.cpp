// End-to-end test of the recognition engine: real JPEGs in, detection,
// alignment, embedding, storage, matching. The one test in this repository
// that would have caught the accuracy bugs the P0 audit found, because none
// of them threw or crashed. They just quietly made recognition worse:
// channels in the wrong order, no landmark alignment, an aspect ratio
// distorted by a non-uniform resize.
//
// It is also the only guard on the thresholds. AUTO_MATCH_THRESHOLD and
// GROUPING_THRESHOLD are numbers somebody picked; here they meet two faces
// that really are the same person and two that really are not.
//
// Needs the ML models and the reference portraits:
//   bash scripts/download_models_for_build.sh
//   bash tests/fixtures/download_faces.sh
//
// It also needs OpenCV >= 4.8: the YuNet 2023mar model uses layers the
// 4.6 DNN importer refuses, which is why this lane runs on a different
// base image from the rest of the suite.

#include <QtTest>
#include <QTemporaryDir>
#include <QImageReader>
#include <QImage>
#include <QPainter>
#include <QFileInfo>

#include "facedetector.h"
#include "facerecognizer.h"
#include "facedatabase.h"

// Mirrored from FacePipeline, which cannot be linked here without dragging
// in the whole QtConcurrent orchestration
static const float kAutoMatchThreshold = 0.72f;
static const float kGroupingThreshold = 0.68f;

class TstPipeline : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void init();
    void cleanup();

    void findsExactlyOneFaceInEachPortrait();
    void embeddingsAre128DimensionalUnitVectors();
    void theSamePersonMatchesAcrossTheYears();
    void differentPeopleStayBelowTheGroupingThreshold();
    void theGapBetweenSameAndDifferentIsWide();
    void aFaceMatchesItselfExactly();
    void recognitionSurvivesHeavyRecompression();
    void recognitionSurvivesDownscaling();
    void findsNoFaceInAPhotoWithoutOne();
    void embeddingsSurviveTheDatabaseRoundTrip();

private:
    QString fixture(const QString &name) const;
    QImage loadPhoto(const QString &path) const;
    FaceDetection detectOne(const QImage &image) const;
    FaceEmbedding embed(const QImage &image) const;
    FaceEmbedding embedFixture(const QString &name) const;

    FaceDetector *m_detector = nullptr;
    FaceRecognizer *m_recognizer = nullptr;
    QTemporaryDir *m_dir = nullptr;
};

void TstPipeline::initTestCase()
{
    const QString models = QStringLiteral(NAMI_MODELS_DIR);
    const QString yunet = models + "/face_detection_yunet_2023mar.onnx";
    const QString sface = models + "/face_recognition_sface_2021dec.onnx";

    if (!QFileInfo::exists(yunet) || !QFileInfo::exists(sface)) {
        QSKIP("ML models missing: run scripts/download_models_for_build.sh");
    }
    if (!QFileInfo::exists(fixture("meir-2016.jpg"))) {
        QSKIP("reference portraits missing: run tests/fixtures/download_faces.sh");
    }
}

void TstPipeline::init()
{
    m_dir = new QTemporaryDir;
    QVERIFY(m_dir->isValid());

    const QString models = QStringLiteral(NAMI_MODELS_DIR);
    m_detector = new FaceDetector;
    m_recognizer = new FaceRecognizer;

    QVERIFY2(m_detector->loadModel(models + "/face_detection_yunet_2023mar.onnx"),
             "YuNet failed to load; OpenCV older than 4.8 cannot read this model");
    QVERIFY2(m_recognizer->loadModel(models + "/face_recognition_sface_2021dec.onnx"),
             "SFace failed to load");
}

void TstPipeline::cleanup()
{
    delete m_recognizer;
    m_recognizer = nullptr;
    delete m_detector;
    m_detector = nullptr;
    delete m_dir;
    m_dir = nullptr;
}

QString TstPipeline::fixture(const QString &name) const
{
    return QStringLiteral(NAMI_FIXTURES_DIR) + "/faces/" + name;
}

QImage TstPipeline::loadPhoto(const QString &path) const
{
    // Exactly how FacePipeline reads a photo: the bboxes it stores are in
    // the coordinates of the EXIF-oriented image
    QImageReader reader(path);
    reader.setAutoTransform(true);
    return reader.read();
}

FaceDetection TstPipeline::detectOne(const QImage &image) const
{
    const QVector<FaceDetection> faces = m_detector->detect(image);
    return faces.isEmpty() ? FaceDetection() : faces.first();
}

FaceEmbedding TstPipeline::embed(const QImage &image) const
{
    const FaceDetection face = detectOne(image);
    if (face.landmarks.isEmpty()) {
        return FaceEmbedding();
    }
    return m_recognizer->extractEmbedding(FaceDetector::qImageToCvMat(image), face);
}

FaceEmbedding TstPipeline::embedFixture(const QString &name) const
{
    return embed(loadPhoto(fixture(name)));
}

void TstPipeline::findsExactlyOneFaceInEachPortrait()
{
    const QStringList names = { "meir-2016.jpg", "meir-2013.jpg", "koch-2023.jpg" };

    for (const QString &name : names) {
        const QImage photo = loadPhoto(fixture(name));
        QVERIFY2(!photo.isNull(), qPrintable(name));

        const QVector<FaceDetection> faces = m_detector->detect(photo);
        QCOMPARE(faces.size(), 1);

        const FaceDetection &face = faces.first();
        // Studio portraits: anything below this means the detector has
        // regressed, not that the photo is hard
        QVERIFY2(face.confidence > 0.9f, qPrintable(name));
        // Five landmarks are what the aligner warps onto the ArcFace
        // template; without them recognition falls back to a raw crop
        QCOMPARE(face.landmarks.size(), 5);

        QVERIFY(face.bbox.x() >= 0.0 && face.bbox.y() >= 0.0);
        QVERIFY(face.bbox.right() <= 1.0 && face.bbox.bottom() <= 1.0);
        QVERIFY(face.bbox.width() > 0.05 && face.bbox.width() < 0.9);
    }
}

void TstPipeline::embeddingsAre128DimensionalUnitVectors()
{
    const FaceEmbedding embedding = embedFixture("meir-2016.jpg");

    QCOMPARE(int(embedding.size()), 128);

    // Cosine similarity is computed as a bare dot product, so it is only a
    // cosine if the vectors really are unit length
    double norm = 0.0;
    for (float value : embedding) {
        norm += double(value) * double(value);
    }
    QVERIFY(qAbs(std::sqrt(norm) - 1.0) < 1e-4);
}

void TstPipeline::theSamePersonMatchesAcrossTheYears()
{
    // Same person, 2013 and 2016: different hair, clothing, pose and
    // lighting. This is the case exemplar matching exists for.
    const float score = FaceRecognizer::computeSimilarity(embedFixture("meir-2016.jpg"),
                                                          embedFixture("meir-2013.jpg"));

    QVERIFY2(score > kAutoMatchThreshold,
             qPrintable(QString("same person scored %1, below the auto-match "
                                "threshold %2").arg(score).arg(kAutoMatchThreshold)));

    // Measured at 0.848. Asserting well above the threshold rather than just
    // past it: a pipeline that has quietly lost alignment still clears 0.72
    // on two studio portraits, and would go on failing on real photos.
    QVERIFY2(score > 0.78f,
             qPrintable(QString("same person scored only %1").arg(score)));
}

void TstPipeline::differentPeopleStayBelowTheGroupingThreshold()
{
    const FaceEmbedding koch = embedFixture("koch-2023.jpg");

    // Both are NASA studio portraits of women of similar build and
    // colouring, so this is not a free pass
    const float against2016 = FaceRecognizer::computeSimilarity(embedFixture("meir-2016.jpg"), koch);
    const float against2013 = FaceRecognizer::computeSimilarity(embedFixture("meir-2013.jpg"), koch);

    QVERIFY2(against2016 < kGroupingThreshold,
             qPrintable(QString("different people scored %1").arg(against2016)));
    QVERIFY2(against2013 < kGroupingThreshold,
             qPrintable(QString("different people scored %1").arg(against2013)));
}

void TstPipeline::theGapBetweenSameAndDifferentIsWide()
{
    const FaceEmbedding meir2016 = embedFixture("meir-2016.jpg");
    const FaceEmbedding meir2013 = embedFixture("meir-2013.jpg");
    const FaceEmbedding koch = embedFixture("koch-2023.jpg");

    const float same = FaceRecognizer::computeSimilarity(meir2016, meir2013);
    const float different = FaceRecognizer::computeSimilarity(meir2016, koch);

    // Measured at 0.848 vs 0.627. What matters for the thresholds is not
    // either number but the room between them: it is what lets a single
    // setting work across a gallery instead of being tuned per person.
    QVERIFY2(same - different > 0.12f,
             qPrintable(QString("same %1 vs different %2 leaves no room for a "
                                "threshold").arg(same).arg(different)));
}

void TstPipeline::aFaceMatchesItselfExactly()
{
    const FaceEmbedding embedding = embedFixture("meir-2016.jpg");

    QVERIFY(qAbs(FaceRecognizer::computeSimilarity(embedding, embedding) - 1.0f) < 1e-4f);
}

void TstPipeline::recognitionSurvivesHeavyRecompression()
{
    const QImage original = loadPhoto(fixture("meir-2016.jpg"));

    // A photo that went through a messaging app and came back
    const QString path = m_dir->filePath("recompressed.jpg");
    QVERIFY(original.save(path, "JPG", 55));

    const float score = FaceRecognizer::computeSimilarity(embed(original),
                                                          embed(loadPhoto(path)));

    QVERIFY2(score > kAutoMatchThreshold,
             qPrintable(QString("recompression dropped the score to %1").arg(score)));
}

void TstPipeline::recognitionSurvivesDownscaling()
{
    const QImage original = loadPhoto(fixture("meir-2013.jpg"));
    const QImage small = original.scaled(original.size() / 4, Qt::KeepAspectRatio,
                                         Qt::SmoothTransformation);

    const float score = FaceRecognizer::computeSimilarity(embed(original), embed(small));

    QVERIFY2(score > kAutoMatchThreshold,
             qPrintable(QString("downscaling dropped the score to %1").arg(score)));
}

void TstPipeline::findsNoFaceInAPhotoWithoutOne()
{
    // A false positive here costs the user an identify prompt about a wall
    QImage landscape(800, 600, QImage::Format_RGB32);
    QPainter painter(&landscape);
    QLinearGradient gradient(0, 0, 0, 600);
    gradient.setColorAt(0.0, QColor(120, 170, 220));
    gradient.setColorAt(1.0, QColor(200, 190, 150));
    painter.fillRect(landscape.rect(), gradient);
    painter.end();

    QCOMPARE(m_detector->detect(landscape).size(), 0);
}

void TstPipeline::embeddingsSurviveTheDatabaseRoundTrip()
{
    const QImage photo = loadPhoto(fixture("meir-2016.jpg"));
    const FaceDetection face = detectOne(photo);
    const FaceEmbedding embedding = embed(photo);
    QVERIFY(!embedding.empty());

    FaceDatabase db;
    QVERIFY(db.open(m_dir->filePath("pipeline.db")));

    const int photoId = db.addPhoto(fixture("meir-2016.jpg"), QDateTime::currentDateTime(),
                                    photo.width(), photo.height());
    QVERIFY(photoId > 0);
    QVERIFY(db.addFace(photoId, face.bbox, face.confidence, embedding) > 0);

    const QVector<Face> stored = db.getFacesForPhoto(photoId);
    QCOMPARE(stored.size(), 1);

    // A serialisation that loses precision does not fail loudly: it comes
    // back as an embedding that no longer matches the face it was taken from
    const float score = FaceRecognizer::computeSimilarity(embedding, stored.first().embedding);
    QVERIFY2(qAbs(score - 1.0f) < 1e-4f,
             qPrintable(QString("the stored embedding scored %1 against the "
                                "one that was saved").arg(score)));

    QCOMPARE(stored.first().bbox, face.bbox);
    db.close();
}

QTEST_MAIN(TstPipeline)
#include "tst_pipeline.moc"
