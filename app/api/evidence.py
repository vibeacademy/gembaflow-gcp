"""Evidence page routes — preview-only.

Mounted by app/main.py only when ENVIRONMENT=preview. Production routing
is untouched: this module is never imported in production.

Routes:
  GET /          — HTML evidence page for non-technical reviewers
  GET /healthz/evidence — JSON probe results for the agent to check headlessly
"""

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from app.evidence import SECTIONS
from app.templates import templates

router = APIRouter()


def _run_sections() -> list[dict]:
    results = []
    for section in SECTIONS:
        try:
            passed, observation = section.probe()
        except Exception as exc:
            passed = False
            observation = f"Probe raised an exception: {exc}"
        results.append(
            {
                "name": section.name,
                "passed": passed,
                "observation": observation,
                "explanation": section.explanation,
            }
        )
    return results


@router.get("/")
async def evidence_page(request: Request):
    sections = _run_sections()
    all_passed = all(s["passed"] for s in sections)
    return templates.TemplateResponse(
        request,
        "evidence.html",
        {"sections": sections, "all_passed": all_passed},
    )


@router.get("/healthz/evidence")
async def evidence_json() -> JSONResponse:
    sections = _run_sections()
    all_passed = all(s["passed"] for s in sections)
    return JSONResponse({"passed": all_passed, "sections": sections})
