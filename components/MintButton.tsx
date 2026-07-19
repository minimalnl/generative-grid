"use client";

import { useState } from "react";

// Jouw prijstrap. Elke trede: tot welk nummer, en de prijs in LYX.
const PRIJS_TRAP = [
  { tot: 100, prijs: 1 },
  { tot: 200, prijs: 2 },
  { tot: 300, prijs: 5 },
  { tot: 500, prijs: 10 },
  { tot: 1000, prijs: 42 },
];

const MAX_SUPPLY = 1000;

// Bepaalt de prijs voor een gegeven mint-nummer (1-based).
function prijsVoor(nummer: number): number | null {
  if (nummer > MAX_SUPPLY) return null; // uitverkocht
  for (const trede of PRIJS_TRAP) {
    if (nummer <= trede.tot) return trede.prijs;
  }
  return null;
}

export function MintButton() {
  // Voor nu simuleren we de teller lokaal. Later komt dit uit het contract.
  const [gemint, setGemint] = useState(0);

  const volgendeNummer = gemint + 1;
  const prijs = prijsVoor(volgendeNummer);
  const uitverkocht = prijs === null;

  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 8, marginTop: 16 }}>
      <div style={{ fontSize: 14, color: "#555" }}>
        {uitverkocht
          ? `Uitverkocht — ${MAX_SUPPLY} van ${MAX_SUPPLY} gemint`
          : `Mint #${volgendeNummer} van ${MAX_SUPPLY}`}
      </div>

      <button
        onClick={() => !uitverkocht && setGemint(gemint + 1)}
        disabled={uitverkocht}
        style={{
          padding: "10px 20px",
          border: "none",
          background: uitverkocht ? "#999" : "#353839",
          color: "#fff",
          fontWeight: 600,
          cursor: uitverkocht ? "default" : "pointer",
        }}
      >
        {uitverkocht ? "Uitverkocht" : `Mint voor ${prijs} LYX`}
      </button>

      <div style={{ fontSize: 12, color: "#999" }}>
        Al gemint: {gemint}
      </div>
    </div>
  );
}