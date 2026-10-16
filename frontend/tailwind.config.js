/** @type {import('tailwindcss').Config} */
// Sunwai palette: institutional, calm, legible.
//   ink     - text and the sidebar
//   paper   - page background (cool, not cream)
//   line    - borders
//   seal    - the one accent: a deep green, like an official seal
//   veil    - marks confidential / sensitive material
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: { DEFAULT: "#172033", soft: "#4A5468", faint: "#7A8396" },
        paper: "#F4F5F7",
        line: "#DFE2E8",
        seal: { DEFAULT: "#24584B", soft: "#E3EEEA", dark: "#173D34" },
        veil: { DEFAULT: "#5A3E99", soft: "#EEE9F7" },
        high: { DEFAULT: "#B42318", soft: "#FDECEA" },
        medium: { DEFAULT: "#9A5B00", soft: "#FDF3E1" },
        low: { DEFAULT: "#4A5468", soft: "#EDEFF3" },
      },
      fontFamily: { sans: ['"Public Sans Variable"', "system-ui", "sans-serif"] },
      fontSize: { "2xs": ["0.6875rem", "1rem"] },
    },
  },
  plugins: [],
};
