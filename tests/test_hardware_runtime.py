from pathlib import Path
import shutil
import sys
import pytest
from hardware_runtime import run_tool


def test_nonzero_tool_status_preserves_stderr(tmp_path):
    result = run_tool([sys.executable, '-c', 'import sys; print("bad", file=sys.stderr); sys.exit(3)'], tmp_path)
    assert result['status'] == 'failed'
    assert result['exit_code'] == 3
    assert result['stderr'].strip() == 'bad'


def test_missing_tool_is_blocked(tmp_path):
    result = run_tool([str(tmp_path/'unavailable-vivado')], tmp_path)
    assert result['status'] == 'blocked'
    assert result['exit_code'] is None


def test_upstream_nms_rtl(tmp_path):
    if not shutil.which('iverilog'):
        pytest.skip('Install Icarus Verilog to run the RTL integration test')
    root = Path(__file__).resolve().parents[1]
    result = run_tool(['iverilog','-g2012','-s','tb_dataerai_nms','-o',str(tmp_path/'nms.vvp'),
                       str(root/'08_hls_design/TopCrop.sv'),str(root/'tests/tb_dataerai_nms.sv')],tmp_path)
    assert result['exit_code'] == 0, result['stderr']
    result = run_tool(['vvp', str(tmp_path/'nms.vvp')], tmp_path)
    assert result['exit_code'] == 0, result
    assert 'PASS: NMS' in result['stdout']
    assert (tmp_path/'nms-waveform.vcd').stat().st_size > 0
