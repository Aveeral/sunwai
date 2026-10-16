import { Link } from "react-router-dom";

export default function NotFound() {
  return (
    <div className="mx-auto max-w-md px-6 py-24 text-center">
      <h1 className="text-2xl font-semibold text-ink">Page not found</h1>
      <p className="mt-2 text-ink-soft">This address doesn't match any page in Sunwai.</p>
      <Link to="/" className="mt-6 inline-block text-seal underline">Go to the start</Link>
    </div>
  );
}
