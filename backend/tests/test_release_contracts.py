from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "supabase" / "migrations"


def test_migrations_include_base_schema_before_pipeline_alters():
    names = sorted(path.name for path in MIGRATIONS.glob("*.sql"))

    assert names[0] == "20260523000000_base_schema.sql"
    base = (MIGRATIONS / names[0]).read_text(encoding="utf-8")
    assert "create table if not exists public.recordings" in base
    assert "create table if not exists public.tasks" in base


def test_analysis_kind_is_consistent_across_schema_and_edge_function():
    migration_text = "\n".join(
        path.read_text(encoding="utf-8") for path in MIGRATIONS.glob("*.sql")
    )
    edge = (ROOT / "supabase" / "functions" / "submit-recording" / "index.ts").read_text(
        encoding="utf-8"
    )

    assert "gemini_eval" not in migration_text
    assert "gemini_eval" not in edge
    assert '"gpt_eval"' in edge
    assert 'gpt_eval: "gemini-eval.json"' in edge


def test_security_migration_has_atomic_authorized_review_and_storage_rls():
    sql = (
        MIGRATIONS / "20260525000000_secure_atomic_workflow.sql"
    ).read_text(encoding="utf-8").lower()

    assert "function public.review_submission" in sql
    assert "for update of s, t" in sql
    assert "v_lab_id <> auth.uid()" in sql
    assert "earnings_submission_id_unique" in sql
    assert "owner_id = auth.uid()::text" in sql
    assert "collectors read recording bundle objects" in sql
    assert "labs read task recording objects" in sql
    assert 'drop policy if exists "service role full access"' in sql
    assert "with check (true)" not in sql


def test_modal_kickoff_failure_is_retryable_and_visible_to_client():
    edge = (ROOT / "supabase" / "functions" / "submit-recording" / "index.ts").read_text(
        encoding="utf-8"
    )
    ios = (
        ROOT
        / "iosApp"
        / "DataCollector"
        / "Services"
        / "UploadService.swift"
    ).read_text(encoding="utf-8")

    assert 'req.method === "GET"' in edge
    assert "analysis_already_started" in edge
    assert "hourlySubmissionLimit" in edge
    assert "}, 429);" in edge
    assert "analysis_started: false" in edge
    assert "}, 502);" in edge
    assert 'result?["analysis_started"] as? Bool == true' in ios

