import { lazy, Suspense, type ReactNode } from "react";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import type { Role } from "./api/types";
import Layout from "./components/Layout";
import { Spinner } from "./components/ui";
import { AuthProvider, homeFor, useAuth } from "./lib/auth";
import { ClockProvider } from "./lib/clock";
import AccessLog from "./pages/AccessLog";
import AllComplaints from "./pages/AllComplaints";
import Appeals from "./pages/Appeals";
import CommitteeCases from "./pages/CommitteeCases";
import ComplaintDetail from "./pages/ComplaintDetail";
import FileComplaint from "./pages/FileComplaint";
import HandlerHistory from "./pages/HandlerHistory";
import HandlerQueue from "./pages/HandlerQueue";
import Login from "./pages/Login";
import MyComplaints from "./pages/MyComplaints";
import NotFound from "./pages/NotFound";
import Scripts from "./pages/Scripts";
import SecurityDemo from "./pages/SecurityDemo";
import TriageQueue from "./pages/TriageQueue";

// The dashboard pulls in the charting library; load it only when opened.
const Dashboard = lazy(() => import("./pages/Dashboard"));

/** Pages behind the login. The role list only hides menu entries the role
 *  can't use; the database still refuses anything the role may not do. */
function Private({ children }: { children: ReactNode }) {
  const { me, loading } = useAuth();
  if (loading) return <div className="p-10"><Spinner /></div>;
  if (!me) return <Navigate to="/" replace />;
  return <Layout><Suspense fallback={<Spinner />}>{children}</Suspense></Layout>;
}

function Home() {
  const { me, loading } = useAuth();
  if (loading) return <div className="p-10"><Spinner /></div>;
  return me ? <Navigate to={homeFor(me.role as Role)} replace /> : <Login />;
}

export default function App() {
  return (
    <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
      <AuthProvider>
        <ClockProvider>
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/file" element={<Private><FileComplaint /></Private>} />
            <Route path="/complaints" element={<Private><MyComplaints /></Private>} />
            <Route path="/c/:id" element={<Private><ComplaintDetail /></Private>} />
            <Route path="/scripts" element={<Private><Scripts /></Private>} />
            <Route path="/queue" element={<Private><HandlerQueue /></Private>} />
            <Route path="/history" element={<Private><HandlerHistory /></Private>} />
            <Route path="/committee" element={<Private><CommitteeCases /></Private>} />
            <Route path="/triage" element={<Private><TriageQueue /></Private>} />
            <Route path="/appeals" element={<Private><Appeals /></Private>} />
            <Route path="/dashboard" element={<Private><Dashboard /></Private>} />
            <Route path="/all" element={<Private><AllComplaints /></Private>} />
            <Route path="/access-log" element={<Private><AccessLog /></Private>} />
            <Route path="/security" element={<Private><SecurityDemo /></Private>} />
            <Route path="*" element={<NotFound />} />
          </Routes>
        </ClockProvider>
      </AuthProvider>
    </BrowserRouter>
  );
}
