#include "whisper.h"
#include "common-whisper.h"
#include "json.hpp"
#include <csignal>
#include <atomic>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

// Private, line-delimited JSON on the parent's pipes. No sockets or background daemon.
static_assert(std::atomic<bool>::is_always_lock_free, "Cancellation must be signal-safe");
static std::atomic<bool> cancelled{false};
static void cancel_inference(int) { cancelled.store(true, std::memory_order_relaxed); }
static void reply(const nlohmann::json & value) { std::cout << value.dump() << '\n' << std::flush; }

int main(int argc, char ** argv) {
    std::string model, language = "ko";
    bool gpu = true;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--model" && i + 1 < argc) model = argv[++i];
        else if (arg == "--language" && i + 1 < argc) language = argv[++i];
        else if (arg == "--no-gpu") gpu = false;
        else { reply({{"type", "error"}, {"error", "Invalid worker arguments"}}); return 2; }
    }
    if (model.empty()) return 2;
    std::signal(SIGUSR1, cancel_inference);
    std::signal(SIGPIPE, SIG_DFL); // Exit if the owning app has gone away.
    auto context_params = whisper_context_default_params();
    context_params.use_gpu = gpu;
    context_params.flash_attn = true; // Same as pinned whisper-cli defaults.
    std::unique_ptr<whisper_context, decltype(&whisper_free)> context(
        whisper_init_from_file_with_params(model.c_str(), context_params), whisper_free);
    if (!context) { reply({{"type", "error"}, {"error", "Model could not be loaded"}}); return 1; }
    reply({{"type", "ready"}});
    std::string line;
    while (std::getline(std::cin, line)) {
        std::string id;
        try {
            const auto request = nlohmann::json::parse(line);
            id = request.at("id").get<std::string>();
            const auto path = request.at("path").get<std::string>();
            cancelled = 0;
            // Parent only sends cancellation once this handshake has been received.
            reply({{"type", "started"}, {"id", id}});
            std::vector<float> samples;
            std::vector<std::vector<float>> channels;
            if (!read_audio_data(path, samples, channels, false) || samples.empty() || samples.size() > 16000 * 300) {
                reply({{"type", "error"}, {"id", id}, {"error", "Invalid or oversized audio"}});
                continue;
            }
            auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
            const auto beam = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH);
            params.beam_search.beam_size = beam.beam_search.beam_size;
            params.strategy = params.beam_search.beam_size > 1 ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY;
            params.n_threads = 4;
            params.language = language.c_str();
            params.translate = false;
            params.no_context = true; // Never feed a preview or earlier dictation into final decoding.
            params.no_timestamps = true;
            params.print_realtime = params.print_progress = params.print_timestamps = params.print_special = false;
            params.suppress_nst = false;
            params.abort_callback = [](void *) { return cancelled != 0; };
            params.encoder_begin_callback = [](whisper_context *, whisper_state *, void *) { return cancelled == 0; };
            const int status = cancelled ? 1 : whisper_full(context.get(), params, samples.data(), int(samples.size()));
            if (cancelled) { reply({{"type", "cancelled"}, {"id", id}}); continue; }
            if (status != 0) { reply({{"type", "error"}, {"id", id}, {"error", "Whisper inference failed"}}); continue; }
            std::string text;
            for (int i = 0; i < whisper_full_n_segments(context.get()); ++i) {
                if (i) text += '\n';
                text += whisper_full_get_segment_text(context.get(), i);
            }
            reply({{"type", "result"}, {"id", id}, {"text", text}});
        } catch (const std::exception & error) {
            reply({{"type", "error"}, {"id", id}, {"error", error.what()}});
        }
    }
    return 0;
}
