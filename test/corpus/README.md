# Detection corpus

Reference photographs used by `test/face_detector_corpus_test.dart`. They keep
the cascade honest: the synthetic fixtures in `test/support` only exercise the
opt-in heuristic detector, so without real photographs a regression in the LBP
evaluator would go unnoticed.

Every file is in the public domain and was downloaded from Wikimedia Commons.
The images are excluded from the published package by `.pubignore`, so they add
nothing to the download size of `package:dartface`.

Run `dart run tool/download_corpus.dart` to fetch them again. The tool verifies
each file against a recorded SHA-256 digest, so the expected detections in
`test/corpus/corpus.dart` always describe the exact bytes under test.

| File                                  | Source                                                                                                                         | License       |
|---------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|---------------|
| `group_apollo11_crew.jpg`             | [Apollo 11 Crew.jpg](https://commons.wikimedia.org/wiki/File:Apollo_11_Crew.jpg)                                               | Public domain |
| `group_obama_family.jpg`              | [Obama Family.jpg](https://commons.wikimedia.org/wiki/File:Obama_Family.jpg)                                                   | Public domain |
| `group_solvay_1927.jpg`               | [Solvay conference 1927.jpg](https://commons.wikimedia.org/wiki/File:Solvay_conference_1927.jpg)                               | Public domain |
| `negative_big_bend.jpg`               | [Big Bend National Park PB112573.jpg](https://commons.wikimedia.org/wiki/File:Big_Bend_National_Park_PB112573.jpg)             | Public domain |
| `negative_blue_marble.png`            | [Blue Marble 2002.png](https://commons.wikimedia.org/wiki/File:Blue_Marble_2002.png)                                           | Public domain |
| `negative_statue_of_liberty_face.jpg` | [Face of Statue of Liberty.jpg](https://commons.wikimedia.org/wiki/File:Face_of_Statue_of_Liberty.jpg)                         | Public domain |
| `negative_usda_lab_cat.jpg`           | [USDA lab cat.jpg](https://commons.wikimedia.org/wiki/File:USDA_lab_cat.jpg)                                                   | Public domain |
| `portrait_albert_einstein.jpg`        | [Albert Einstein Head.jpg](https://commons.wikimedia.org/wiki/File:Albert_Einstein_Head.jpg)                                   | Public domain |
| `portrait_buzz_aldrin.jpg`            | [Buzz Aldrin.jpg](https://commons.wikimedia.org/wiki/File:Buzz_Aldrin.jpg)                                                     | Public domain |
| `portrait_katherine_johnson.jpg`      | [Katherine Johnson 1983.jpg](https://commons.wikimedia.org/wiki/File:Katherine_Johnson_1983.jpg)                               | Public domain |
| `portrait_mae_jemison.jpg`            | [Mae Carol Jemison.jpg](https://commons.wikimedia.org/wiki/File:Mae_Carol_Jemison.jpg)                                         | Public domain |
| `portrait_marie_curie.jpg`            | [Marie Curie c1920.jpg](https://commons.wikimedia.org/wiki/File:Marie_Curie_c1920.jpg)                                         | Public domain |
| `portrait_michelle_obama.jpg`         | [Michelle Obama 2013 official portrait.jpg](https://commons.wikimedia.org/wiki/File:Michelle_Obama_2013_official_portrait.jpg) | Public domain |
| `portrait_neil_armstrong.jpg`         | [Neil Armstrong pose.jpg](https://commons.wikimedia.org/wiki/File:Neil_Armstrong_pose.jpg)                                     | Public domain |
| `portrait_ruth_bader_ginsburg.jpg`    | [Ruth Bader Ginsburg official portrait.jpg](https://commons.wikimedia.org/wiki/File:Ruth_Bader_Ginsburg_official_portrait.jpg) | Public domain |
| `portrait_sally_ride.jpg`             | [Sally Ride (1984).jpg](https://commons.wikimedia.org/wiki/File:Sally_Ride_(1984).jpg)                                         | Public domain |

The expected bounding boxes in `test/corpus/corpus.dart` were read back from
the detector and then checked against the photographs by hand. They are stated
with wide tolerances because the cascade snaps boxes to its pyramid steps.

Most faces also carry hand-labelled eye and mouth positions, read off zoomed
crops with a coordinate grid. They calibrate and guard the landmark estimator;
`dart run test/corpus/measure_landmarks.dart` reports the error against them.
Mae Jemison, Ruth Bader Ginsburg, and the three faces in
`group_apollo11_crew.jpg` were labelled after the estimator was tuned, so they
measure it on several photographs that took no part in that tuning.
