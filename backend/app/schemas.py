"""Request bodies (validated by FastAPI before anything reaches the database)."""
from typing import Literal

from pydantic import BaseModel, Field


class LoginIn(BaseModel):
    person_id: int
    role: str | None = None            # default: the most specific role the person holds


class PreviewIn(BaseModel):
    description: str = Field(min_length=10, max_length=4000)


class PartyIn(BaseModel):
    person_id: int | None = None
    party_role: Literal["Respondent", "Witness"] = "Respondent"
    stated_role: Literal["Student", "Faculty", "Staff", "Unknown"] = "Unknown"
    description: str | None = Field(default=None, max_length=200)


class FileIn(BaseModel):
    analysis_id: str
    visibility: Literal["Public", "Confidential", "Anonymous"] = "Public"
    contact_consent: bool = True
    details: dict[str, str] = {}
    people: list[PartyIn] | None = None


class AnswerIn(BaseModel):
    seq_no: int
    answer: str = Field(min_length=1, max_length=500)


class RateIn(BaseModel):
    rating: int = Field(ge=1, le=5)


class TextIn(BaseModel):
    text: str = Field(min_length=3, max_length=1000)


class StatusIn(BaseModel):
    status: Literal["InProgress", "Resolved", "Rejected"]
    resolution_outcome: Literal["Upheld", "Dismissed", "ActionTaken", "Fixed",
                                "InsufficientInfo"] | None = None
    resolution_note: str | None = Field(default=None, max_length=500)
    note: str | None = Field(default=None, max_length=150)


class DisputeIn(BaseModel):
    question_no: int
    marks_awarded: float
    marks_claimed: float
    reason: str = Field(min_length=3, max_length=300)


class ReevaluationIn(BaseModel):
    script_id: int
    disputes: list[DisputeIn] = Field(min_length=1)


class DecideDisputeIn(BaseModel):
    question_no: int
    decision: Literal["Accepted", "Partial", "Rejected"]
    revised_marks: float | None = None


class ConfirmTriageIn(BaseModel):
    category_id: int
    priority: Literal["Low", "Medium", "High"] | None = None


class DecideAppealIn(BaseModel):
    status: Literal["Upheld", "Dismissed"]
    outcome: str = Field(min_length=3, max_length=500)


class ClockIn(BaseModel):
    offset_hours: float | None = None
    advance_hours: float | None = None


class TryAccessIn(BaseModel):
    action: str
