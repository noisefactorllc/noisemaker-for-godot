"""Shared filter for the gpu-floor engine-exit noise in windowed Godot probes.

The Apple-M4 gpu floor's Godot 4.7 processes print one unrelated engine-exit
ERROR line at every windowed run — the macOS certificate-store lookup:

    ERROR: Condition "ret != noErr" is true. Returning: ""
       at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)

It appears even in probes that never load the port backend (e.g.
test_editor_import_and_export_preserve_raw_shader_templates), so a blanket
`assertNotIn("ERROR:")` scan is a floor-level false positive, not a port
defect. Windowed suites scan the output with the exact noise line removed;
every other ERROR — including leaked-handle warnings ("Attempted to free
invalid ID", "Leaked instance/RID/resource", "still registered in the
device") — is still detected. The filter removes ONLY those two exact lines.
"""

NOISE_ERROR = 'ERROR: Condition "ret != noErr" is true. Returning: ""'
NOISE_AT = "at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)"


def without_engine_exit_noise(output: str) -> str:
    lines = output.splitlines(keepends=True)
    out = []
    skip_next_at = False
    for line in lines:
        if skip_next_at and NOISE_AT in line:
            skip_next_at = False
            continue
        if line.rstrip("\n") == NOISE_ERROR:
            skip_next_at = True
            continue
        out.append(line)
    return "".join(out)
