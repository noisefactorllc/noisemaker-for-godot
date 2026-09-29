"""Import raw shader templates and retain them byte-for-byte in exported packs."""
import hashlib
import json
import os
from pathlib import Path

try:
    from parity.godot_floor_noise import without_engine_exit_noise
except ImportError:  # direct discovery (unittest discover -s parity)
    from godot_floor_noise import without_engine_exit_noise
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
GODOT = os.environ.get('GODOT', '/Applications/Godot.app/Contents/MacOS/Godot')


class ShaderImportTests(unittest.TestCase):
    def test_editor_import_and_export_preserve_raw_shader_templates(self):
        with tempfile.TemporaryDirectory(prefix='nm-shader-import-') as tmp:
            root = Path(tmp)
            shaders = REPO / 'godot/addons/noisemaker/shaders'
            shutil.copytree(shaders, root / 'shaders')
            expected = {'res://shaders/' + p.relative_to(shaders).as_posix():
                        hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in shaders.rglob('*.glsl')}
            self.assertGreater(len(expected), 300)
            (root / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Shader import regression"\n')
            (root / 'verify.gd').write_text('''extends SceneTree
func _init() -> void:
    var expected = %s
    for path in expected:
        if FileAccess.get_sha256(path) != expected[path]:
            push_error("Missing or changed shader: " + path)
            quit(1)
            return
    print("RAW_SHADERS_OK ", expected.size())
    quit(0)
''' % json.dumps(expected))
            (root / 'export_presets.cfg').write_text('''[preset.0]
name="Raw shader pack"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
[preset.0.options]
application/modify_resources=false
''')
            def run(*args):
                result = subprocess.run([GODOT, '--path', str(root), *args],
                                        capture_output=True, text=True, timeout=180)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output[-12000:])
                self.assertNotIn('ShaderFile', output, output[-12000:])
                self.assertNotIn('SCRIPT ERROR', output, output[-12000:])
                self.assertNotIn('ERROR:', without_engine_exit_noise(output), output[-12000:])
                return output
            run('--editor', '--import', '--position', '5000,5000')
            run('--headless', '--export-pack', 'Raw shader pack', str(root / 'test.pck'))
            shutil.rmtree(root / 'shaders')  # The verifier must read the pack, not loose files.
            output = run('--headless', '--main-pack', str(root / 'test.pck'), '--script', 'res://verify.gd')
            self.assertIn('RAW_SHADERS_OK ' + str(len(expected)), output)


if __name__ == '__main__':
    unittest.main()
