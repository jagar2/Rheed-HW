import json
from pathlib import Path

import numpy as np
import pytest

from tests.helpers import make_tracker, COLLECTION_ID


def test_failed_cell_cannot_be_finalized_as_success(tmp_path):
    tracker, client, _ = make_tracker(tmp_path, collection_id=COLLECTION_ID)
    tracker.record_cell(source="raise ValueError('bad data')", success=False,
                        error=ValueError("bad data"))
    tracker.finish()
    summary = json.loads((tracker.run_dir / "run-summary.json").read_text())
    assert summary["run_summary"]["status"] == "failed"
    assert client.metadata_updates[-1][1]["metadata"]["completion"]["status"] == "failed"


def test_nested_arrays_are_saved_losslessly(tmp_path):
    tracker, client, _ = make_tracker(tmp_path)
    values = {"growth_1": np.arange(3000).reshape(30, 100)}
    tracker.record_cell(source="raw_data = load()", assigned_names=["raw_data"],
                        user_ns={"raw_data": values})
    output = next(x for x in client.uploads if x["path"].suffix == ".npz")
    with np.load(output["path"], allow_pickle=False) as data:
        np.testing.assert_array_equal(data["growth_1"], values["growth_1"])


def test_secret_named_array_is_not_serialized(tmp_path):
    tracker, client, _ = make_tracker(tmp_path)
    tracker.record_cell(source="api_token = secret()", assigned_names=["api_token"],
                        user_ns={"api_token": np.arange(10)})
    assert not any(x["path"].suffix == ".npz" for x in client.uploads)


def test_registered_file_is_hash_pinned_and_linked(tmp_path):
    tracker, client, _ = make_tracker(tmp_path, collection_id=COLLECTION_ID)
    artifact = tmp_path / "model.weights.h5"
    artifact.write_bytes(b"weights")
    asset_id = tracker.capture_file(artifact, role="model", relationship="generated_by")
    upload = next(x for x in client.uploads if x["asset_id"] == asset_id)
    assert upload["kwargs"]["metadata"]["output"]["sha256"] == "9a129038d9a00aed0cf6a7ea059ca50a813449061ab87848cf1a13eafdf33b2c"
    assert upload["kwargs"]["collection_id"] == COLLECTION_ID
    assert any(a == asset_id and b == tracker.run_asset_id for a, b, _ in client.relationships)


def test_model_weights_saved_even_when_model_is_callable(tmp_path):
    class Model:
        def __call__(self): pass
        def to_json(self): return '{"class_name":"test"}'
        def get_weights(self): return [np.arange(12).reshape(3, 4)]
    tracker, client, _ = make_tracker(tmp_path)
    tracker.record_cell(source="model = Model()", assigned_names=["model"],
                        user_ns={"model": Model()})
    output = next(x for x in client.uploads if x["path"].suffix == ".npz")
    with np.load(output["path"], allow_pickle=False) as data:
        np.testing.assert_array_equal(data["weight_0"], np.arange(12).reshape(3, 4))
        assert json.loads(str(data["architecture_json"]))["class_name"] == "test"


def test_collection_is_sealed_for_all_outputs(tmp_path, monkeypatch):
    tracker, client, _ = make_tracker(tmp_path, collection_id=COLLECTION_ID)
    tracker.collection_id = "changed"
    monkeypatch.setenv("DATAERAI_COLLECTION_ID", "changed")
    tracker.record_cell(source="x = 1", assigned_names=["x"], user_ns={"x": 1})
    tracker.finish()
    assert all(x["kwargs"]["collection_id"] == COLLECTION_ID for x in client.uploads)


def test_upload_failure_propagates_with_local_evidence(tmp_path):
    tracker, client, _ = make_tracker(tmp_path)
    def fail(*args, **kwargs): raise RuntimeError("upload unavailable")
    client.upload = fail
    with pytest.raises(RuntimeError, match="upload unavailable"):
        tracker.record_cell(source="x = 1", assigned_names=["x"], user_ns={"x": 1})
    assert (tracker.run_dir / "cell-0001" / "assigned-values.json").exists()


def test_raw_execution_evidence_survives_upload_failure(tmp_path):
    tracker, client, _ = make_tracker(tmp_path)
    def fail(*args, **kwargs): raise RuntimeError('unavailable')
    client.upload = fail
    with pytest.raises(RuntimeError):
        tracker.record_cell(source='x = 1', stdout='scientific result', assigned_names=['x'],user_ns={'x':1})
    raw=json.loads((tracker.run_dir/'cell-0001'/'execution-local.json').read_text())
    assert raw['source'] == 'x = 1'
    assert raw['stdout'] == 'scientific result'


def test_run_ids_and_titles_distinguish_repeated_executions(tmp_path):
    tracker, client, shell = make_tracker(tmp_path)
    from dataerai_notebook import NotebookProvenance
    again = NotebookProvenance(tracker.notebook_path, client=client, shell=shell).start()
    assert tracker.run_id != again.run_id
    runs = [x for x in client.uploads if x["kwargs"]["metadata"]["record_kind"] == "notebook_run"]
    assert runs[0]["kwargs"]["title"] != runs[1]["kwargs"]["title"]


def test_imported_model_class_is_not_a_model_instance(tmp_path):
    class Model:
        def to_json(self): return '{}'
        def get_weights(self): return []
    tracker, client, _ = make_tracker(tmp_path)
    tracker.record_cell(source='from keras import Model', user_ns={'Model': Model})
    assert not any(x['path'].suffix == '.npz' for x in client.uploads)


def test_explicit_failure_wins_over_capture_error_status(tmp_path):
    tracker, client, _ = make_tracker(tmp_path)
    tracker.errors.append({'message':'capture failed'})
    tracker.finish(status='failed')
    assert client.metadata_updates[-1][1]['metadata']['completion']['status'] == 'failed'
