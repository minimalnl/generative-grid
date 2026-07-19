"use client";

import { UpProvider } from "@/components/upProvider";
import { P5Player } from "@/components/P5Player";
import { useState, useEffect } from "react";

// Import the LUKSO web-components library
let promise: Promise<unknown> | null = null;
if (typeof window !== "undefined") {
  promise = import("@lukso/web-components");
}

/**
 * Toont de p5-speler gecentreerd op de pagina.
 */
function MainContent() {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    promise?.then(() => {
      setMounted(true);
    });
  }, []);

  if (!mounted) {
    return null;
  }

  return (
    <main style={{ minHeight: "100dvh", display: "flex", alignItems: "center", justifyContent: "center" }}>
      <P5Player />
    </main>
  );
}

/**
 * Root: MainContent binnen de UpProvider context.
 */
export default function Home() {
  return (
    <UpProvider>
      <MainContent />
    </UpProvider>
  );
}