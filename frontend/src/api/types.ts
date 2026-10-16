export type Role =
  | "sunwai_student" | "sunwai_handler" | "sunwai_triage" | "sunwai_icc"
  | "sunwai_antiragging" | "sunwai_sgrc" | "sunwai_ombudsperson" | "sunwai_admin";

export type Priority = "Low" | "Medium" | "High";
export type Status =
  | "Filed" | "Triaged" | "NeedsInfo" | "Assigned" | "InProgress" | "Escalated"
  | "Resolved" | "Rejected" | "Closed" | "Appealed";

export interface Profile {
  person_id: number; full_name: string; person_type: string; department: string;
  hostel: string | null; room_no: string | null;
}

export interface Me {
  person_id: number; name: string; person_type: string; unit: string; posts: string | null;
  roles: Role[]; role: Role; role_label: string; role_labels: Record<Role, string>;
  profile: Profile | null;
}

export interface DemoPerson {
  person_id: number; name: string; posts: string | null; unit: string;
  role: Role; role_label: string; roles: Role[]; blurb: string;
}
export interface DemoGroup { title: string; people: DemoPerson[] }

export interface Category {
  category_id: number; name: string; domain: string; sensitivity: "Normal" | "Sensitive";
  base_priority: Priority | null; sla_hours: number | null; anonymous_allowed: boolean;
}

export interface Candidate {
  person_id: number; full_name: string; person_type: string; department: string;
  connection: string; score: number;
}
export interface PreviewPerson {
  ref: string | null; party_role: "Respondent" | "Witness";
  stated_role: "Student" | "Faculty" | "Staff" | "Unknown";
  description: string | null; name: string | null; candidates: Candidate[];
}
export interface ChecklistItem {
  field: string; mandatory: boolean; question: string; value: string | null;
  source: "AI" | "Profile" | null; status: "ok" | "missing" | "optional";
}
export interface Preview {
  analysis_id: string; engine: string; redacted_text: string; category: Category;
  confidence: number; auto_accepted: boolean; urgency: Priority; priority: Priority;
  sensitive: boolean; summary: string; reasoning: string; checklist: ChecklistItem[];
  people: PreviewPerson[]; route_hint: string; anonymous_allowed: boolean;
}

export interface MyComplaint {
  complaint_id: number; description: string; visibility: string; status: Status;
  priority: Priority | null; filed_at: string; category: string | null; domain: string | null;
  unit: string | null; location_text: string | null; handled_by: string | null;
  due_at: string | null; deadline_state: string | null; resolution_outcome: string | null;
  resolution_note: string | null; resolved_at: string | null; feedback_rating: number | null;
  reopened_from: number | null; open_questions: number;
}

export interface Overview {
  complaint_id: number; description: string; visibility: string; status: Status;
  priority: Priority | null; filed_at: string; category_id: number | null; category: string | null;
  domain: string | null; sensitivity: string | null; unit: string | null; location_text: string | null;
  resolution_outcome: string | null; resolution_note: string | null; resolved_at: string | null;
  feedback_rating: number | null; reopened_from: number | null; ai_summary: string | null;
  ai_confidence: number | null; decision_type: string | null; routing_reason: string | null;
  assigned_person_id: number | null; assigned_person: string | null;
  assigned_committee_id: number | null; assigned_committee: string | null;
  due_at: string | null; hours_pending: number | null; deadline_state: string | null;
}

export type Hidden = "hidden";
export interface Clarification {
  complaint_id: number; seq_no: number; field_name: string | null; question: string;
  asked_by: string; answer: string | null; asked_at: string; answered_at: string | null;
}
export interface ComplaintPage {
  complaint: Overview;
  access_logged: boolean;
  me: { is_complainant: boolean; is_handler: boolean; is_committee: boolean };
  details: { field_name: string; value: string; source: string }[] | Hidden;
  identity: { name: string; contact_consent: boolean } | null | Hidden;
  parties: { party_no: number; party_role: string; stated_role: string; description: string | null; name: string | null }[] | Hidden;
  clarifications: Clarification[] | Hidden;
  routing: { decision_id: number; decision_type: string; reason: string; decided_at: string; due_at: string | null; assigned_person: string | null; committee: string | null }[] | Hidden;
  exclusions: { decision_id: number; person: string; reason_code: string; reason: string }[] | Hidden;
  timeline: { at: string; kind: string; title: string; detail: string | null }[] | Hidden;
  ai: { urgency: string; confidence: number; sensitivity_flag: boolean; summary: string; suggested_category: string | null; reviewed_at: string | null; reviewed_by: string | null } | null | Hidden;
  disputes: { question_no: number; marks_awarded: number; marks_claimed: number; student_reason: string; reviewer_decision: string | null; revised_marks: number | null }[] | Hidden;
  marks_changes: { question_no: number; old_marks: number; new_marks: number; changed_at: string; changed_by: string; reason: string | null }[] | Hidden;
  appeals: { appeal_id: number; filed_on: string; grounds: string; status: string; outcome: string | null; heard_by: string }[] | Hidden;
  reopened_as: number | null;
}

export interface QueueRow {
  complaint_id: number; category: string; domain: string; priority: Priority; status: Status;
  unit: string | null; location_text: string | null; ai_summary: string | null; filed_at: string;
  due_at: string | null; deadline_state: string | null; hours_pending: number | null;
  decision_type: string | null; routing_reason: string | null;
}
export interface CommitteeRow {
  complaint_id: number; committee_type: string; committee: string; category: string;
  priority: Priority; status: Status; ai_summary: string | null; filed_at: string;
  due_at: string | null; deadline_state: string | null; routing_reason: string | null;
  recused_members: string | null;
}
export interface TriageRow {
  complaint_id: number; description: string; filed_at: string; status: Status; visibility: string;
  suggested_category_id: number | null; ai_suggested_category: string | null;
  confidence: number | null; urgency: Priority | null; sensitivity_flag: boolean | null; summary: string | null;
}
export interface AppealRow {
  appeal_id: number; complaint_id: number; filed_on: string; grounds: string; status: string;
  outcome: string | null; category: string; resolution_outcome: string | null;
  resolution_note: string | null; assigned_person: string | null; assigned_committee: string | null;
}
export interface Script {
  script_id: number; total_marks: number | null; shown_on: string | null; exam_type: string;
  exam_date: string; max_marks: number; course_code: string; title: string; reevaluation_id: number | null;
}
export interface Analytics {
  summary: { total_complaints: number; open_complaints: number; escalated_now: number; waiting_for_info: number; avg_hours_to_resolve: number | null; avg_rating: number | null };
  weekly_trend: { week: string; domain: string; complaints: number; change_vs_last_week: number | null; running_total: number }[];
  hotspots: { unit: string; domain: string; complaints: number; last_30_days: number }[];
  by_office: { office: string; complaints: number; resolved: number; avg_hours_to_resolve: number | null; escalated: number; speed_rank: number }[];
  sla_breaches: { domain: string; total: number; breached: number; breach_pct: number }[];
  ai_accuracy: { final_category: string; triaged: number; ai_correct: number; accuracy_pct: number; avg_confidence: number; human_reviewed: number }[];
  clarifications: { category: string; complaints: number; needed_clarification: number; pct: number; questions_asked: number }[];
}
export interface Attempt { action: string; label: string; sql: string }
export interface AttemptResult extends Attempt {
  role: Role; allowed: boolean; error?: string; rows?: Record<string, unknown>[]; rowcount?: number;
}
