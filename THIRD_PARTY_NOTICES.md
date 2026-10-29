# Third-party components

- Engine: [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp), MIT license, v1.9.5 / commit `d1be6fde11ac6e0407606b4e42fe72d34add8037`. Its license is copied into the built app. It includes ggml and its upstream notices in `vendor/whisper.cpp`.
- Models: multilingual Whisper Small and Medium, published in ggml format by [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp). Model repository revision `5359861c739e955e79d9a303bcbc70fb988958b1` is pinned. Whisper [code and model weights](https://github.com/openai/whisper#license) are released under the MIT license. Models are downloaded separately into the user's Application Support folder.
- The app uses macOS AppKit, AVFoundation, Carbon, and ApplicationServices system frameworks. No third-party Swift package or cloud transcription API is used.
- The resident worker uses the upstream copy of [JSON for Modern C++](https://github.com/nlohmann/json), version 3.11.2, under the MIT license below.

The original application code is released under the [MIT License](LICENSE). Third-party components retain their respective copyright and license notices. This repository is a personal local app, not an official OpenAI or whisper.cpp product.

## JSON for Modern C++ — MIT License

Copyright (c) 2013-2022 Niels Lohmann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
