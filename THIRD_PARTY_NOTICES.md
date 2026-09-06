# Third-party notices

Dartface's implementation code is original and covered by the repository's MIT license. The generated constants in `lib/src/detector/generated/lbp_frontal_face_cascade.dart` contain trained classifier parameters derived from the following separately licensed model.

## Improved LBP frontal-face cascade

- Source: `lbpcascade_frontalface_improved.xml` from the OpenCV 4.x repository
- Source URL: https://github.com/opencv/opencv/blob/4.x/data/lbpcascades/lbpcascade_frontalface_improved.xml
- Source SHA-256: `7c31331d494f20e216b397ad99d824d92ab91ebb15db3bcda6a2f8e684d238d3`
- Generated representation: numeric stage thresholds, category masks, leaf values, and LBP feature rectangles

The source model contains this notice:

```text
Copyright (c) 2017, Puttemans Steven, Can Ergun and Toon Goedeme
(KU Leuven, EAVISE Research Group, Jan Pieter De Nayerlaan 5,
Sint-Katelijne-Waver, Belgium).
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
   * The name of Contributor may not used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

The model authors request this citation for research use:

Steven Puttemans, Can Ergun, and Toon Goedemé, “Improving Open Source Face Detection by Combining an Adapted Cascade Classification Pipeline and Active Learning,” 12th International Conference on Computer Vision Theory and Applications, 2017.
