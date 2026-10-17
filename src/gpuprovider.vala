// SPDX-License-Identifier: GPL-3.0-or-later

public class GpuProvider : Provider {
    private bool nvidia_warning_logged;

    public GpuProvider() {
        base("gpu", {"load"}, "p");
    }

    private void add_nvidia_values(ref double total, ref uint count) {
        if (Environment.find_program_in_path("nvidia-smi") == null)
            return;

        string output;
        string errors;
        int status;
        try {
            Process.spawn_sync(
                null,
                {"nvidia-smi", "--query-gpu=utilization.gpu",
                    "--format=csv,noheader,nounits"},
                null,
                SpawnFlags.SEARCH_PATH,
                null,
                out output,
                out errors,
                out status
            );
        } catch (SpawnError error) {
            if (!this.nvidia_warning_logged) {
                warning("Unable to query NVIDIA GPU utilization: %s", error.message);
                this.nvidia_warning_logged = true;
            }
            return;
        }

        if (status != 0) {
            if (!this.nvidia_warning_logged) {
                warning("nvidia-smi failed: %s", errors.strip());
                this.nvidia_warning_logged = true;
            }
            return;
        }

        foreach (var line in output.strip().split("\n")) {
            var value = line.strip();
            if (!Regex.match_simple("^[0-9]+$", value))
                continue;

            var percentage = double.parse(value);
            if (percentage >= 0 && percentage <= 100) {
                total += percentage;
                ++count;
            }
        }
    }

    private void add_amd_values(ref double total, ref uint count) {
        try {
            var cards = Dir.open("/sys/class/drm");
            string? card;
            while ((card = cards.read_name()) != null) {
                if (!Regex.match_simple("^card[0-9]+$", card))
                    continue;

                string content;
                var path = @"/sys/class/drm/$card/device/gpu_busy_percent";
                try {
                    FileUtils.get_contents(path, out content);
                } catch (Error error) {
                    continue;
                }

                var value = content.strip();
                if (!Regex.match_simple("^[0-9]+$", value))
                    continue;

                var percentage = double.parse(value);
                if (percentage >= 0 && percentage <= 100) {
                    total += percentage;
                    ++count;
                }
            }
        } catch (Error error) {
            return;
        }
    }

    public override void update() {
        double total = 0;
        uint count = 0;
        this.add_nvidia_values(ref total, ref count);
        this.add_amd_values(ref total, ref count);

        this.values[0] = count > 0 ? total / count / 100 : 0;
    }
}
