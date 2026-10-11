"use strict";
const used = document.getElementById("used");
const elapsed = document.getElementById("elapsed");
function renderPace() {
  const usage = Number(used.value);
  const expected = Number(elapsed.value);
  const delta = usage - expected;
  const color = usage >= 100 || delta > 15 ? "var(--red)" : delta > 3 ? "var(--yellow)" : "var(--green)";
  document.querySelector(".demo").style.setProperty("--signal", color);
  document.getElementById("used-value").textContent = `${usage}%`;
  document.getElementById("elapsed-value").textContent = `${expected}%`;
  document.getElementById("menu-delta").textContent = `${delta >= 0 ? "+" : ""}${delta}%`;
  document.querySelector(".fill").style.width = `${usage}%`;
  document.querySelector(".marker").style.left = `${expected}%`;
  document.getElementById("verdict").textContent = delta === 0 ? "Exactly on perfect pacing." : `${Math.abs(delta)} percentage points ${delta > 0 ? "ahead of" : "behind"} perfect pacing.`;
}
used.addEventListener("input", renderPace);
elapsed.addEventListener("input", renderPace);
renderPace();
