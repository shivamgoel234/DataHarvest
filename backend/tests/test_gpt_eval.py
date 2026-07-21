from types import SimpleNamespace

from backend.analyzers.gpt_eval import (
    build_evaluation_prompt,
    evaluate_video_file,
    response_schema,
)
from backend.contracts import GPTEvaluation


def test_prompt_includes_summary_and_task():
    prompt = build_evaluation_prompt("Pick up the cup.")

    assert "Pick up the cup." in prompt
    assert "summary" in prompt
    assert "score" in prompt
    assert "success_reasoning" in prompt


def test_gpt_evaluation_rejects_out_of_range_score():
    payload = {
        "summary": "The video shows a hand near a cup.",
        "success": True,
        "success_reasoning": "The cup is lifted.",
        "score": 11,
        "score_reasoning": "Too high.",
    }

    try:
        GPTEvaluation.model_validate(payload)
    except Exception as exc:
        assert "score" in str(exc)
    else:
        raise AssertionError("Expected score validation to fail")


def test_response_schema_names_expected_fields():
    schema = response_schema()

    assert set(schema["properties"]) == {
        "summary",
        "success",
        "success_reasoning",
        "score",
        "score_reasoning",
    }



def test_evaluator_uses_gemini_file_and_model_apis(tmp_path, monkeypatch):
    video = tmp_path / "video.mp4"
    video.write_bytes(b"video")
    uploaded = SimpleNamespace(name="files/video", state="ACTIVE")

    class Files:
        def __init__(self):
            self.deleted = []

        def upload(self, *, file):
            assert file == str(video.resolve())
            return uploaded

        def delete(self, *, name):
            self.deleted.append(name)

    class Models:
        def generate_content(self, **kwargs):
            assert kwargs["model"] == "gemini-test"
            assert kwargs["contents"][0] is uploaded
            return SimpleNamespace(
                text='{"summary":"Cup lifted.","success":true,'
                '"success_reasoning":"Visible completion.","score":8,'
                '"score_reasoning":"Minor hesitation."}'
            )

    client = SimpleNamespace(files=Files(), models=Models())
    monkeypatch.setattr("backend.analyzers.gpt_eval._response_config", lambda: {})
    result = evaluate_video_file(
        video_path=video,
        task_description="Lift the cup",
        model="gemini-test",
        client=client,
    )

    assert result.score == 8
    assert client.files.deleted == ["files/video"]
