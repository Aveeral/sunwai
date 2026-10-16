const dateFmt = new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short" });
const dateTimeFmt = new Intl.DateTimeFormat("en-IN", {
  day: "numeric", month: "short", hour: "numeric", minute: "2-digit",
});

export const fmtDate = (s: string | null | undefined) => (s ? dateFmt.format(new Date(s)) : "–");
export const fmtDateTime = (s: string | null | undefined) => (s ? dateTimeFmt.format(new Date(s)) : "–");

/** "in 5 h", "3 h overdue", "2 d ago" relative to a reference time (demo clock aware). */
export function relative(s: string | null | undefined, now = Date.now()): string {
  if (!s) return "–";
  const diffH = (new Date(s).getTime() - now) / 36e5;
  const abs = Math.abs(diffH);
  const txt = abs < 1 ? `${Math.max(1, Math.round(abs * 60))} min` : abs < 48 ? `${Math.round(abs)} h` : `${Math.round(abs / 24)} d`;
  return diffH >= 0 ? `in ${txt}` : `${txt} ago`;
}

/** Human labels for complaint detail fields (from category_requirement). */
export const FIELD_LABELS: Record<string, string> = {
  hostel: "Hostel",
  room_or_floor: "Room or floor",
  since_when: "Since when",
  meal: "Meal",
  meal_date: "Day",
  building_room: "Building and room",
  item: "What is broken",
  lab_name: "Lab",
  equipment: "Equipment",
  course: "Course",
  clash_details: "Clash (day and slot)",
  assessment: "Assessment",
  exam: "Exam",
  question_numbers: "Questions",
  device_or_service: "Service",
  location: "Location",
  respondent_role: "The person is a",
  respondent_identity: "Who it is",
  incident_details: "What happened",
  incident_date: "When",
  witnesses: "Witnesses",
};
export const fieldLabel = (f: string | null) => (f ? FIELD_LABELS[f] ?? f.replace(/_/g, " ") : "Question");

export const STATUS_LABELS: Record<string, string> = {
  Filed: "Filed", Triaged: "Triaged", NeedsInfo: "Needs your reply", Assigned: "Assigned",
  InProgress: "In progress", Escalated: "Escalated", Resolved: "Resolved",
  Rejected: "Rejected", Closed: "Closed", Appealed: "Under appeal",
};
export const OUTCOME_LABELS: Record<string, string> = {
  Upheld: "Upheld", Dismissed: "Dismissed", ActionTaken: "Action taken", Fixed: "Fixed",
  InsufficientInfo: "Closed for lack of information",
};
export const CONFLICT_LABELS: Record<string, string> = {
  Respondent: "is the person complained about",
  Complainant: "filed the complaint",
  OriginalEvaluator: "marked the original answer script",
  ReportsToRespondent: "reports to the person complained about",
  SameDepartment: "is in the same department as the respondent",
};
