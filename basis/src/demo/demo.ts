// Demo library: Physics II, Calculus III and Statics — realistic student notes
// with diagrams, equations, live variables, tables and graphs.

import { INK, type CanvasElement, type Notebook, type Page, type Section, type TemplateKind } from '../models'
import { templateInfo } from '../models/templates'
import { uid } from '../services/id'
import type { LibrarySnapshot } from '../services/storage'
import {
  BLUE,
  GREEN,
  ORANGE,
  PURPLE,
  RED,
  bezier,
  calc,
  charge,
  circlePts,
  eq,
  graph,
  handArrow,
  highlight,
  lerpColor,
  resistorH,
  resistorV,
  ring,
  shape,
  sticky,
  stroke,
  table,
  text,
  title,
  underline,
} from './helpers'

const DAY = 86_400_000

interface PageSpec {
  title: string
  template?: TemplateKind
  elements: CanvasElement[]
  openedAgo?: number // ms ago; undefined = never opened
  zoom?: number
  vpY?: number
}

function build(
  nb: Omit<Notebook, 'id' | 'createdAt' | 'updatedAt' | 'lastOpenedAt'> & { editedAgo: number },
  sections: { title: string; pages: PageSpec[] }[],
): LibrarySnapshot {
  const now = Date.now()
  const notebook: Notebook = {
    id: uid('n_'),
    name: nb.name,
    description: nb.description,
    icon: nb.icon,
    color: nb.color,
    favorite: nb.favorite,
    createdAt: now - 40 * DAY,
    updatedAt: now - nb.editedAgo,
    lastOpenedAt: now - nb.editedAgo,
  }
  const secs: Section[] = []
  const pages: Page[] = []
  sections.forEach((s, si) => {
    const sec: Section = { id: uid('s_'), notebookId: notebook.id, title: s.title, order: si, collapsed: false }
    secs.push(sec)
    s.pages.forEach((p, pi) => {
      const template = p.template ?? 'engineering'
      pages.push({
        id: uid('p_'),
        notebookId: notebook.id,
        sectionId: sec.id,
        title: p.title,
        order: pi,
        template,
        templateOptions: { ...templateInfo(template).defaults },
        elements: p.elements,
        viewport: { x: 40, y: p.vpY ?? 10, zoom: p.zoom ?? 1 },
        createdAt: now - (40 - si * 5 - pi) * DAY,
        updatedAt: now - nb.editedAgo - (sections.length - si) * 3600_000,
        lastOpenedAt: p.openedAgo !== undefined ? now - p.openedAgo : 0,
      })
    })
  })
  return { notebooks: [notebook], sections: secs, pages }
}

// ═════════════════════════════ PHYSICS II ═════════════════════════════

function coulomb(): CanvasElement[] {
  const els: CanvasElement[] = [
    ...title(40, 100, "Coulomb's Law", 'PHYS 2212 · LECTURE 2 · ELECTRIC FORCE BETWEEN POINT CHARGES'),
    underline(42, 146, 300),
    text(40, 190, 'The electrostatic force between two point charges is proportional to the product of the charges and inversely proportional to the square of their separation.', { w: 560 }),
    highlight(52, 300, 330),
    eq(60, 278, 'F = k*q_1*q_2/r^2', 30),
    eq(64, 360, 'k = 1/(4*pi*epsilon_0) ≈ 8.99e9 N*m^2/C^2', 18),
    // Diagram: two charges with force arrows
    shape('line', 120, 520, 400, 520, { dashed: true, width: 1.4, color: '#8b8f97' }),
    ...charge(120, 520, '+'),
    ...charge(400, 520, '-'),
    shape('arrow', 140, 520, 215, 520, { color: ORANGE, width: 2.6 }),
    shape('arrow', 380, 520, 305, 520, { color: ORANGE, width: 2.6 }),
    eq(98, 552, 'q_1', 18),
    eq(380, 552, 'q_2', 18),
    eq(244, 528, 'r', 18),
    eq(170, 474, '\\vec F_{12}', 16, ORANGE),
    eq(300, 474, '\\vec F_{21}', 16, ORANGE),
    text(120, 600, 'Opposite charges attract — forces are equal and opposite (Newton III).', { fontSize: 14, color: '#8b8f97', w: 360 }),
    // Worked example
    text(660, 190, 'Example 2.1', { fontSize: 13, font: 'mono', color: ORANGE, w: 200 }),
    text(660, 214, 'Find the force between a +3 µC and a −5 µC charge separated by 12 cm.', { w: 360, fontSize: 15 }),
    calc(660, 280, '# Given\nq_1 = 3 uC\nq_2 = -5 uC\nr = 12 cm\nk = 8.99e9 N*m^2/C^2\n\n# Force (negative ⇒ attractive)\nF = k*q_1*q_2/r^2', 'Example 2.1', 360),
    sticky(660, 620, 'Constants', 'ε₀ = 8.854 × 10⁻¹² F/m\nk = 8.99 × 10⁹ N·m²/C²\ne = 1.602 × 10⁻¹⁹ C', 'blue', 260),
    ...handArrow([600, 560], [652, 470], 0.25),
    text(470, 580, 'sign tells direction!', { fontSize: 14, color: ORANGE, w: 180 }),
  ]
  return els
}

function pointField(): CanvasElement[] {
  const cx = 230, cy = 470
  const els: CanvasElement[] = [
    ...title(40, 100, 'Electric Field of a Point Charge', 'FIELD = FORCE PER UNIT TEST CHARGE'),
    underline(42, 146, 470),
    eq(50, 200, 'vec(E) = vec(F)/q_0', 26),
    eq(50, 290, 'abs(vec(E)) = k*abs(q)/r^2', 26),
    text(330, 212, 'Field points away from +q and toward −q.', { fontSize: 15, w: 280, color: '#8b8f97' }),
  ]
  // radial field lines
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2
    els.push(shape('arrow', cx + Math.cos(a) * 30, cy + Math.sin(a) * 30, cx + Math.cos(a) * 130, cy + Math.sin(a) * 130, { color: RED, width: 1.8, opacity: 0.85 }))
  }
  els.push(...charge(cx, cy, '+', 20))
  els.push(stroke(circlePts(cx, cy, 80), { color: '#8b8f97', width: 1.2, opacity: 0.6 }))
  els.push(text(cx + 60, cy + 120, 'Gaussian sphere, r', { fontSize: 13, font: 'mono', color: '#8b8f97', w: 200 }))
  els.push(graph(500, 330, 470, 300, [['y = 8.99/x^2', ORANGE], ['y = 2*8.99/x^2', BLUE]], { xmin: 0, xmax: 6, ymin: -1, ymax: 12 }, { xLabel: 'r (m)', yLabel: 'E (N/C) ×10⁹·q' }))
  els.push(text(500, 640, 'E ∝ 1/r² — doubling q doubles the field at every r.', { fontSize: 14, color: '#8b8f97', w: 440 }))
  els.push(ring(178, 320, 150, 40))
  return els
}

function gauss(): CanvasElement[] {
  return [
    ...title(260, 34, "Gauss's Law", 'CORNELL NOTES · FLUX THROUGH CLOSED SURFACES'),
    // Cues
    text(20, 150, 'What is electric flux?', { w: 200, fontSize: 15, color: ORANGE }),
    text(20, 300, 'Why choose a symmetric surface?', { w: 200, fontSize: 15, color: ORANGE }),
    text(20, 520, 'Conductor in equilibrium?', { w: 200, fontSize: 15, color: ORANGE }),
    // Notes
    text(270, 140, 'Flux measures how much field “passes through” a surface:', { w: 520 }),
    eq(290, 180, 'Phi_E = iint(vec(E) * hat(n), A)', 24),
    text(270, 290, 'For ANY closed surface, net flux depends only on enclosed charge:', { w: 560 }),
    highlight(296, 360, 300, '#4ade80'),
    eq(296, 336, 'oint(vec(E), vec(A)) = Q_enc/epsilon_0', 28),
    text(270, 420, 'Pick a surface where E is constant & ⟂ to the surface → E pulls out of the integral.', { w: 560, fontSize: 15 }),
    eq(296, 470, 'E*(4*pi*r^2) = Q/epsilon_0  =>  E = Q/(4*pi*epsilon_0*r^2)', 20),
    text(270, 530, 'Inside a conductor E = 0, excess charge sits on the surface.', { w: 560 }),
    // Sphere sketch
    ...charge(1000, 300, '+', 16),
    stroke(circlePts(1000, 300, 90, 60), { color: BLUE, width: 2 }),
    shape('ellipse', 910, 285, 1090, 315, { dashed: true, color: BLUE, width: 1.4 }),
    shape('arrow', 1000, 210, 1000, 160, { color: ORANGE, width: 2 }),
    shape('arrow', 1090, 300, 1140, 300, { color: ORANGE, width: 2 }),
    shape('arrow', 1064, 236, 1100, 200, { color: ORANGE, width: 2 }),
    eq(1110, 176, 'dvec(A)', 16, ORANGE),
    // Summary
    text(20, 1376, 'Gauss’s law turns a hard surface integral into algebra whenever symmetry makes E constant over the surface. Spheres → point charges; cylinders → line charges; pillboxes → planes.', { w: 900, fontSize: 15 }),
  ]
}

function potential(): CanvasElement[] {
  const els: CanvasElement[] = [
    ...title(40, 100, 'Electric Potential & Work', 'POTENTIAL ENERGY PER UNIT CHARGE'),
    underline(42, 146, 380),
    eq(50, 200, 'V = k*q/r', 26),
    eq(50, 258, '\\Delta V = -\\int_a^b \\vec E\\cdot d\\vec s', 22),
    eq(50, 320, 'W = q*Delta(V),  K = 1/2*m*v^2', 22),
    text(40, 390, 'A proton is accelerated from rest through a 500 V potential difference. Find its final speed.', { w: 480, fontSize: 15 }),
    calc(40, 460, '# Proton through a potential difference\nq = 1.602e-19 C\nm_p = 1.673e-27 kg\ndV = 500 V\n\nW = q*dV\nW -> eV\nv = sqrt(2*W/m_p)\nv -> km/s', 'Accelerated proton', 380),
    sticky(470, 470, 'Check', 'v ≪ c (3×10⁵ km/s), so the classical K = ½mv² is fine.', 'green', 230),
  ]
  // equipotentials
  const cx = 830, cy = 300
  els.push(...charge(cx, cy, '+', 16))
  ;[50, 90, 140, 200].forEach((r, i) => els.push(shape('ellipse', cx - r, cy - r, cx + r, cy + r, { dashed: true, color: lerpColor('#ff6b2c', '#3b82f6', i / 3), width: 1.6 })))
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2 + 0.2
    els.push(shape('arrow', cx + Math.cos(a) * 24, cy + Math.sin(a) * 24, cx + Math.cos(a) * 215, cy + Math.sin(a) * 215, { color: '#8b8f97', width: 1.2, opacity: 0.6 }))
  }
  els.push(text(700, 530, 'Equipotentials (dashed) are always ⟂ to field lines.', { w: 300, fontSize: 14, color: '#8b8f97' }))
  return els
}

function equipotential(): CanvasElement[] {
  const els: CanvasElement[] = [
    ...title(40, 100, 'Dipole Field Sketch', 'FIELD LINES + EQUIPOTENTIALS · DOT GRID'),
    underline(42, 146, 330),
  ]
  const a: [number, number] = [330, 430], b: [number, number] = [630, 430]
  for (let i = -3; i <= 3; i++) {
    if (i === 0) {
      els.push(shape('arrow', a[0] + 22, a[1], b[0] - 22, b[1], { color: RED, width: 1.8 }))
      continue
    }
    const h = i * 55
    els.push(stroke(bezier([a[0] + 14, a[1] + Math.sign(i) * 12], [(a[0] + b[0]) / 2, a[1] + h * 2.1], [b[0] - 14, b[1] + Math.sign(i) * 12], 40), { color: RED, width: 1.8, opacity: 0.8 }))
  }
  els.push(...charge(a[0], a[1], '+', 20), ...charge(b[0], b[1], '-', 20))
  els.push(stroke(bezier([480, 220], [470, 430], [480, 640], 30), { color: BLUE, width: 1.6, opacity: 0.8 }))
  els.push(text(490, 210, 'V = 0 plane', { fontSize: 13, font: 'mono', color: BLUE, w: 120 }))
  els.push(eq(740, 260, 'p = q*d', 22), eq(740, 310, 'V(r) ≈ k*p*cos(theta)/r^2', 20))
  return els
}

function capacitor(): CanvasElement[] {
  const els: CanvasElement[] = [
    ...title(40, 100, 'Parallel-Plate Capacitor', 'CAPACITANCE DEPENDS ONLY ON GEOMETRY'),
    underline(42, 146, 420),
    // plates
    shape('rect', 90, 230, 330, 244, { fill: true, color: RED, width: 1.5 }),
    shape('rect', 90, 380, 330, 394, { fill: true, color: BLUE, width: 1.5 }),
  ]
  for (let i = 0; i < 6; i++) els.push(shape('arrow', 110 + i * 42, 252, 110 + i * 42, 372, { color: ORANGE, width: 1.8 }))
  for (let i = 0; i < 6; i++) els.push(text(104 + i * 42, 200, '+', { fontSize: 18, color: RED, w: 20, font: 'mono' }))
  for (let i = 0; i < 6; i++) els.push(text(104 + i * 42, 398, '−', { fontSize: 18, color: BLUE, w: 20, font: 'mono' }))
  els.push(shape('line', 360, 244, 360, 380, { width: 1.2, color: '#8b8f97' }), eq(372, 296, 'd', 20), eq(150, 440, 'Area A', 16))
  els.push(
    eq(470, 190, 'C = epsilon_0*A/d', 28),
    eq(470, 272, 'Q = C*V', 22),
    eq(470, 318, 'U = 1/2*C*V^2 = Q^2/(2*C)', 22),
    highlight(482, 216, 200),
    calc(470, 400, 'A = 0.02 m^2\nd = 1.5 mm\neps0 = 8.854e-12 F/m\nV = 12 V\n\nC = eps0*A/d\nQ = C*V\nU = 1/2*C*V^2', 'Capacitor design', 330),
    sticky(830, 400, 'Try it', 'Change d in the Variables panel → C, Q and U update instantly.', 'amber', 220),
    ...handArrow([830, 490], [805, 500], 0.1),
  )
  return els
}

function rcCharging(): CanvasElement[] {
  return [
    ...title(40, 100, 'RC Charging — Lab 4', 'MEASURED VS. MODEL · τ = RC'),
    underline(42, 146, 300),
    eq(50, 200, 'V_C(t) = V_0*(1 - e^(-t/tau)),  tau = R*C', 24),
    table(40, 270, ['t (s)', 'V meas (V)', 'V model (V)'], [
      ['0', '0.00', '=12*(1-exp(-A1/2))'],
      ['1', '4.61', '=12*(1-exp(-A2/2))'],
      ['2', '7.55', '=12*(1-exp(-A3/2))'],
      ['3', '9.27', '=12*(1-exp(-A4/2))'],
      ['4', '10.31', '=12*(1-exp(-A5/2))'],
      ['6', '11.38', '=12*(1-exp(-A6/2))'],
      ['8', '11.79', '=12*(1-exp(-A7/2))'],
    ], 'Capacitor voltage'),
    graph(470, 270, 500, 320, [['y = 12*(1 - e^(-x/2))', ORANGE]], { xmin: -0.5, xmax: 10, ymin: -1, ymax: 13.5 }, {
      xLabel: 't (s)',
      yLabel: 'V (V)',
      series: [{ id: uid('s'), label: 'measured', color: BLUE, points: [[0, 0], [1, 4.61], [2, 7.55], [3, 9.27], [4, 10.31], [6, 11.38], [8, 11.79]] }],
    }),
    calc(40, 600, 'R = 10 kohm\nC = 200 uF\ntau = R*C\nt_95 = 3*tau', 'Time constant', 320),
    text(470, 620, 'Model fits within ~2%. At t = 3τ the capacitor reaches 95% of V₀.', { w: 460, fontSize: 15 }),
  ]
}

function kirchhoff(): CanvasElement[] {
  const els: CanvasElement[] = [
    ...title(40, 100, "Kirchhoff's Laws", 'JUNCTION RULE · LOOP RULE'),
    underline(42, 146, 300),
    eq(50, 196, 'sum(I_k, k, 1, n) = 0', 24),
    eq(320, 196, '\\oint \\vec E\\cdot d\\vec l = \\sum_k \\Delta V_k = 0', 22),
  ]
  // circuit: battery on left, R1 top, R2 || R3 on right
  const L = 100, T = 300, R = 520, B = 520
  els.push(
    shape('line', L, T, 230, T),
    resistorH(230, T, 100),
    shape('line', 330, T, R, T),
    shape('line', L, B, R, B),
    shape('line', L, T, L, 380),
    shape('line', L, 440, L, B),
    shape('line', L - 22, 380, L + 22, 380, { width: 3 }),
    shape('line', L - 12, 396, L + 12, 396, { width: 3 }),
    shape('line', L - 22, 412, L + 22, 412, { width: 3 }),
    shape('line', L - 12, 428, L + 12, 428, { width: 3 }),
    shape('line', L, 412, L, 440),
    shape('line', L, 380, L, 380),
    shape('line', 420, T, 420, 360),
    resistorV(420, 360, 100),
    shape('line', 420, 460, 420, B),
    shape('line', R, T, R, 360),
    resistorV(R, 360, 100),
    shape('line', R, 460, R, B),
    eq(270, 262, 'R_1', 18),
    eq(372, 396, 'R_2', 18),
    eq(536, 396, 'R_3', 18),
    eq(40, 392, 'V_s', 18),
    shape('ellipse', 416, T - 4, 424, T + 4, { fill: true }),
    shape('ellipse', 416, B - 4, 424, B + 4, { fill: true }),
    ...handArrow([150, 340], [210, 330], -0.3, GREEN),
    eq(150, 346, 'I', 18, GREEN),
  )
  els.push(
    calc(620, 250, 'V_s = 9 V\nR_1 = 220 ohm\nR_2 = 470 ohm\nR_3 = 330 ohm\n\nR_23 = R_2*R_3/(R_2 + R_3)\nR_eq = R_1 + R_23\nI = V_s/R_eq\nI -> mA\nV_1 = I*R_1\nP = V_s*I -> mW', 'Circuit analysis', 360),
    sticky(40, 580, 'Sign convention', 'Going through a resistor with the current: −IR.\nThrough a battery − → +: +ε.', 'graphite', 300),
  )
  return els
}

function lorentz(): CanvasElement[] {
  const ox = 200, oy = 570
  return [
    ...title(40, 100, 'Magnetic Force — Lorentz', 'MOVING CHARGES IN E AND B FIELDS'),
    underline(42, 146, 380),
    highlight(56, 222, 380, '#38bdf8'),
    eq(50, 200, 'vec(F) = q*(vec(E) + cross(vec(v), vec(B)))', 28),
    eq(50, 270, '|\\vec F_B| = |q|\\,vB\\sin\\theta', 20),
    eq(50, 320, 'r = m*v/(abs(q)*B)', 20),
    // right-hand rule axes
    shape('arrow', ox, oy, ox + 150, oy, { color: RED, width: 2.6 }),
    shape('arrow', ox, oy, ox, oy - 150, { color: BLUE, width: 2.6 }),
    shape('arrow', ox, oy, ox - 90, oy + 80, { color: GREEN, width: 2.6 }),
    eq(ox + 156, oy - 16, 'vec(v)', 18, RED),
    eq(ox - 20, oy - 186, 'vec(B)', 18, BLUE),
    eq(ox - 130, oy + 82, 'vec(F)', 18, GREEN),
    stroke(bezier([ox + 60, oy], [ox + 52, oy - 52], [ox, oy - 60], 16), { color: '#8b8f97', width: 1.4 }),
    eq(ox + 40, oy - 54, 'theta', 16),
    text(80, 690, 'Right-hand rule: fingers along v, curl toward B, thumb = F for +q.', { w: 380, fontSize: 14, color: '#8b8f97' }),
    calc(560, 380, '# Electron in a uniform B field\nq = 1.602e-19 C\nm_e = 9.109e-31 kg\nv = 2e6 m/s\nB = 0.5 mT\n\nF = q*v*B\nr = m_e*v/(q*B)\nr -> cm\nf = q*B/(2*pi*m_e)', 'Cyclotron motion', 380),
  ]
}

function biot(): CanvasElement[] {
  const els: CanvasElement[] = [
    ...title(40, 100, 'Field of a Long Straight Wire', 'BIOT–SAVART → AMPÈRE'),
    underline(42, 146, 400),
    eq(50, 200, 'd(vec(B)) = mu_0/(4*pi) * (I*cross(d(vec(l)), hat(r)))/r^2', 22),
    eq(50, 270, 'B = mu_0*I/(2*pi*r)', 26),
  ]
  const cx = 700, cy = 360
  els.push(shape('ellipse', cx - 10, cy - 10, cx + 10, cy + 10, { fill: true, color: ORANGE }), shape('ellipse', cx - 3, cy - 3, cx + 3, cy + 3, { fill: true, color: ORANGE }))
  ;[50, 95, 145].forEach((r) => els.push(shape('ellipse', cx - r, cy - r, cx + r, cy + r, { color: BLUE, width: 1.6 })))
  els.push(shape('arrow', cx + 95, cy + 6, cx + 95, cy - 10, { color: BLUE, width: 2 }), text(cx + 40, cy + 160, 'I out of page ⊙', { font: 'mono', fontSize: 13, color: '#8b8f97', w: 200 }))
  els.push(calc(40, 360, 'mu0 = 1.2566e-6 H/m\nI = 15 A\nr = 4 cm\nB = mu0*I/(2*pi*r)\nB -> uT', 'Wire field', 320))
  return els
}

// ═════════════════════════════ CALCULUS III ═════════════════════════════

function dotCross(): CanvasElement[] {
  const ox = 140, oy = 720, s = 40
  return [
    ...title(40, 100, 'Dot & Cross Products', 'MATH 2551 · §12.3–12.4'),
    underline(42, 146, 330),
    eq(50, 196, 'dot(vec(a), vec(b)) = abs(vec(a))*abs(vec(b))*cos(theta)', 22),
    eq(50, 248, '\\vec a \\times \\vec b = \\begin{vmatrix} \\hat\\imath & \\hat\\jmath & \\hat k \\\\ a_1 & a_2 & a_3 \\\\ b_1 & b_2 & b_3 \\end{vmatrix}', 20),
    eq(50, 370, 'abs(cross(vec(a), vec(b))) = abs(vec(a))*abs(vec(b))*sin(theta) = "area of parallelogram"', 17),
    // vectors on the graph-paper axes
    shape('arrow', ox, oy, ox + 5 * s, oy - 2 * s, { color: ORANGE, width: 2.6 }),
    shape('arrow', ox, oy, ox + 2 * s, oy - 4 * s, { color: BLUE, width: 2.6 }),
    shape('line', ox + 5 * s, oy - 2 * s, ox + 7 * s, oy - 6 * s, { dashed: true, color: '#8b8f97', width: 1.4 }),
    shape('line', ox + 2 * s, oy - 4 * s, ox + 7 * s, oy - 6 * s, { dashed: true, color: '#8b8f97', width: 1.4 }),
    eq(ox + 5 * s + 8, oy - 2 * s, 'vec(a)', 18, ORANGE),
    eq(ox + 2 * s - 30, oy - 4 * s - 30, 'vec(b)', 18, BLUE),
    calc(560, 420, 'a = [3, -2, 1]\nb = [1, 4, -2]\n\nadotb = dot(a, b)\nc = cross(a, b)\narea = norm(c)\ntheta = acos(adotb/(norm(a)*norm(b)))*180/pi', 'Vector arithmetic', 380),
    sticky(560, 300, 'Orthogonality', 'a · b = 0  ⇔  a ⟂ b\na × b is ⟂ to both a and b', 'blue', 260),
  ]
}

function linesPlanes(): CanvasElement[] {
  // isometric cube
  const c = (x: number, y: number, z: number): [number, number] => [700 + (x - y) * 0.866 * 150, 470 + (x + y) * 0.5 * 150 - z * 150]
  const edges: [[number, number, number], [number, number, number]][] = [
    [[0, 0, 0], [1, 0, 0]], [[0, 0, 0], [0, 1, 0]], [[0, 0, 0], [0, 0, 1]],
    [[1, 0, 0], [1, 1, 0]], [[0, 1, 0], [1, 1, 0]], [[1, 0, 0], [1, 0, 1]],
    [[0, 1, 0], [0, 1, 1]], [[0, 0, 1], [1, 0, 1]], [[0, 0, 1], [0, 1, 1]],
    [[1, 1, 0], [1, 1, 1]], [[1, 0, 1], [1, 1, 1]], [[0, 1, 1], [1, 1, 1]],
  ]
  const els: CanvasElement[] = [
    ...title(40, 100, 'Lines & Planes in ℝ³', 'ISOMETRIC SKETCHING'),
    underline(42, 146, 320),
    eq(50, 200, 'vec(r)(t) = vec(r)_0 + t*vec(v)', 22),
    eq(50, 256, 'dot(vec(n), vec(r) - vec(r)_0) = 0', 22),
    eq(50, 312, 'a*(x - x_0) + b*(y - y_0) + c*(z - z_0) = 0', 20),
  ]
  for (const [p, q] of edges) {
    const [x1, y1] = c(...p)
    const [x2, y2] = c(...q)
    const hidden = p[0] === 0 && p[1] === 0 && p[2] === 0
    els.push(shape('line', x1, y1, x2, y2, { width: 2, dashed: hidden, color: hidden ? '#8b8f97' : INK }))
  }
  // diagonal plane through cube
  const [ax, ay] = c(1, 0, 0), [bx, by] = c(0, 1, 0), [tx, ty] = c(0, 0, 1)
  els.push(stroke([[ax, ay], [bx, by], [tx, ty], [ax, ay]], { color: ORANGE, width: 2.4 }))
  els.push(eq(c(0.25, 0.25, 0.4)[0] + 70, c(0.25, 0.25, 0.4)[1] - 40, 'x + y + z = 1', 16, ORANGE))
  const [nx, ny] = c(0.33, 0.33, 0.33)
  els.push(shape('arrow', nx, ny, nx + 50, ny - 70, { color: BLUE, width: 2.4 }), eq(nx + 52, ny - 96, 'vec(n) = [1, 1, 1]', 16, BLUE))
  return els
}

function partials(): CanvasElement[] {
  return [
    ...title(40, 100, 'Partial Derivatives', '§14.3 · HOLD EVERYTHING ELSE CONSTANT'),
    underline(42, 146, 330),
    eq(50, 196, 'f(x, y) = x^2*y + sin(x*y)', 24),
    eq(50, 256, 'pd(f, x) = 2*x*y + y*cos(x*y)', 22),
    eq(50, 326, 'pd(f, y) = x^2 + x*cos(x*y)', 22),
    eq(50, 396, 'pd(f, x, y) = 2*x + cos(x*y) - x*y*sin(x*y) = pd(f, y, x)', 18),
    text(50, 470, 'Clairaut: mixed partials agree when they are continuous ✓', { w: 440, fontSize: 14, color: GREEN }),
    eq(50, 520, 'grad(f) = [pd(f, x), pd(f, y)]', 22),
    text(50, 600, 'The gradient points in the direction of steepest ascent and is ⟂ to level curves.', { w: 440, fontSize: 15 }),
    graph(540, 190, 440, 360, [['y = 1/x', ORANGE], ['y = 2/x', BLUE], ['y = 4/x', PURPLE], ['y = -1/x', '#14b8a6']], { xmin: -5, xmax: 5, ymin: -5, ymax: 5 }, { xLabel: 'x', yLabel: 'y' }),
    text(540, 560, 'Level curves of g(x,y) = xy (hyperbolas, xy = c)', { w: 440, fontSize: 13, color: '#8b8f97', font: 'mono' }),
    ring(170, 545, 140, 40, GREEN),
  ]
}

function gradient(): CanvasElement[] {
  return [
    ...title(40, 100, 'Directional Derivatives & Gradient', '§14.6'),
    underline(42, 146, 460),
    eq(50, 200, 'D_u(f) = dot(grad(f), hat(u))', 24),
    eq(50, 260, 'max(D_u(f)) = abs(grad(f))', 22),
    calc(50, 330, '# f(x,y) = x^2 y + sin(xy) at (1, 2)\nx0 = 1\ny0 = 2\nfx = 2*x0*y0 + y0*cos(x0*y0)\nfy = x0^2 + x0*cos(x0*y0)\ng = [fx, fy]\nsteepest = norm(g)', 'Gradient at a point', 380),
  ]
}

function doubleIntegrals(): CanvasElement[] {
  return [
    ...title(40, 100, 'Double Integrals', '§15.2 · TYPE I & TYPE II REGIONS'),
    underline(42, 146, 300),
    eq(50, 200, '\\iint_R f(x,y)\\,dA = \\int_{0}^{1}\\!\\int_{x^2}^{x} f(x,y)\\,dy\\,dx', 22),
    eq(50, 272, '\\text{Area}(R) = \\int_0^1 (x - x^2)\\,dx = \\tfrac{1}{6}', 22),
    graph(520, 180, 440, 380, [['y = x', ORANGE], ['y = x^2', BLUE]], { xmin: -0.2, xmax: 1.3, ymin: -0.2, ymax: 1.3 }, { xLabel: 'x', yLabel: 'y' }),
    text(50, 350, 'Region R lies between y = x² (below) and y = x (above) for 0 ≤ x ≤ 1.', { w: 420, fontSize: 15 }),
    text(50, 420, 'Reversing the order (Type II):', { w: 420, fontSize: 15 }),
    eq(70, 460, '\\int_{0}^{1}\\!\\int_{y}^{\\sqrt{y}} f(x,y)\\,dx\\,dy', 22),
    sticky(50, 560, 'Exam tip', 'Always sketch the region first — the bounds come from the picture, not the integrand.', 'rose', 300),
  ]
}

function triple(): CanvasElement[] {
  const cx = 720, cy = 380
  return [
    ...title(40, 100, 'Triple Integrals — Spherical', '§15.8'),
    underline(42, 146, 400),
    eq(50, 200, 'x = rho*sin(phi)*cos(theta),  y = rho*sin(phi)*sin(theta),  z = rho*cos(phi)', 18),
    highlight(60, 280, 300, '#a78bfa'),
    eq(50, 258, 'dV = rho^2*sin(phi)*d(rho)*d(phi)*d(theta)', 22),
    eq(50, 330, '\\iiint_{B} dV = \\int_0^{2\\pi}\\!\\int_0^{\\pi}\\!\\int_0^{R} \\rho^2\\sin\\phi\\,d\\rho\\,d\\phi\\,d\\theta = \\tfrac{4}{3}\\pi R^3', 19),
    stroke(circlePts(cx, cy, 130, 64), { width: 2.2 }),
    shape('ellipse', cx - 130, cy - 30, cx + 130, cy + 30, { dashed: true, color: '#8b8f97', width: 1.4 }),
    shape('arrow', cx, cy, cx, cy - 190, { width: 1.6 }),
    shape('arrow', cx, cy, cx + 190, cy + 20, { width: 1.6 }),
    shape('arrow', cx, cy, cx - 120, cy + 110, { width: 1.6 }),
    shape('line', cx, cy, cx + 70, cy - 90, { color: ORANGE, width: 2.4 }),
    shape('ellipse', cx + 66, cy - 94, cx + 74, cy - 86, { fill: true, color: ORANGE }),
    eq(cx + 40, cy - 78, 'rho', 18, ORANGE),
    eq(cx + 8, cy - 70, 'phi', 16),
    eq(cx + 8, cy - 205, 'z', 16),
  ]
}

function vectorField(): CanvasElement[] {
  const els: CanvasElement[] = [
    ...title(40, 100, 'Vector Fields', '§16.1 · ROTATIONAL FIELD F = ⟨−y, x⟩'),
    underline(42, 146, 300),
    eq(50, 196, '\\vec F(x,y) = \\langle -y,\\ x \\rangle', 24),
    eq(50, 250, 'curl(vec(F)) = (pd(Q, x) - pd(P, y))*hat(k) = 2*hat(k)', 20),
    eq(50, 330, 'div(vec(F)) = pd(P, x) + pd(Q, y) = 0', 20),
    text(50, 400, 'Pure rotation: no sources or sinks (div = 0), constant circulation density (curl = 2).', { w: 400, fontSize: 15 }),
    sticky(50, 490, 'Physical picture', 'Velocity field of a rigid disc spinning counter-clockwise — like a turntable.', 'blue', 300),
  ]
  const cx = 740, cy = 400, s = 46
  for (let i = -4; i <= 4; i++)
    for (let j = -4; j <= 4; j++) {
      if (i === 0 && j === 0) continue
      const x = i, y = -j // screen y down
      const vx = -y, vy = x
      const mag = Math.hypot(vx, vy)
      const len = 14 + mag * 3.2
      const ux = (vx / mag) * len, uy = (vy / mag) * len
      const px = cx + i * s, py = cy + j * s
      els.push(shape('arrow', px - ux / 2, py + uy / 2, px + ux / 2, py - uy / 2, { color: lerpColor('#3b82f6', '#ff6b2c', Math.min(1, mag / 5.6)), width: 1.7 }))
    }
  els.push(shape('line', cx - 4.6 * s, cy, cx + 4.6 * s, cy, { width: 1, color: '#8b8f97', opacity: 0.6 }))
  els.push(shape('line', cx, cy - 4.6 * s, cx, cy + 4.6 * s, { width: 1, color: '#8b8f97', opacity: 0.6 }))
  return els
}

function greens(): CanvasElement[] {
  const pts: [number, number][] = []
  for (let i = 0; i <= 80; i++) {
    const a = (i / 80) * Math.PI * 2
    const r = 120 + 26 * Math.sin(3 * a) + 10 * Math.cos(5 * a)
    pts.push([720 + Math.cos(a) * r * 1.2, 400 + Math.sin(a) * r])
  }
  return [
    ...title(40, 100, "Line Integrals & Green's Theorem", '§16.2–16.4'),
    underline(42, 146, 470),
    eq(50, 200, '\\int_C \\vec F\\cdot d\\vec r = \\int_a^b \\vec F(\\vec r(t))\\cdot \\vec r\\,\'(t)\\,dt', 18),
    highlight(60, 290, 420, '#4ade80'),
    eq(50, 262, '\\oint_C P\\,dx + Q\\,dy = \\iint_D \\left(\\frac{\\partial Q}{\\partial x} - \\frac{\\partial P}{\\partial y}\\right) dA', 22),
    text(50, 340, 'C positively oriented (counter-clockwise), simple and closed; D is the region it bounds.', { w: 420, fontSize: 15 }),
    stroke(pts, { width: 2.4, color: BLUE }),
    ...handArrow([830, 290], [790, 268], 0.1, BLUE),
    eq(700, 390, 'D', 26),
    eq(870, 500, 'C', 22, BLUE),
  ]
}

// ═════════════════════════════ STATICS ═════════════════════════════

function beam(): CanvasElement[] {
  const y = 380
  return [
    ...title(40, 100, 'Simply Supported Beam — FBD', 'ENGR 2110 · HW 5 · PROBLEM 3'),
    underline(42, 146, 420),
    shape('rect', 100, y, 700, y + 24, { fill: true, width: 2 }),
    shape('triangle', 80, y + 24, 120, y + 60, { width: 2 }),
    shape('ellipse', 670, y + 24, 700, y + 54, { width: 2 }),
    shape('line', 60, y + 60, 140, y + 60, { width: 2 }),
    shape('line', 640, y + 56, 730, y + 56, { width: 2 }),
    shape('arrow', 400, y - 110, 400, y - 4, { color: RED, width: 3 }),
    eq(410, y - 120, 'P = 12 kN', 18, RED),
    shape('arrow', 100, y + 150, 100, y + 64, { color: BLUE, width: 2.6 }),
    shape('arrow', 685, y + 150, 685, y + 60, { color: BLUE, width: 2.6 }),
    eq(70, y + 154, 'R_A', 18, BLUE),
    eq(660, y + 154, 'R_B', 18, BLUE),
    shape('line', 100, y + 200, 400, y + 200, { width: 1.2, color: '#8b8f97' }),
    shape('line', 400, y + 200, 700, y + 200, { width: 1.2, color: '#8b8f97' }),
    eq(230, y + 206, 'a = 2.5 m', 15),
    eq(520, y + 206, 'b = 3.5 m', 15),
    eq(780, 200, 'sum(F_y) = 0,  sum(M_A) = 0', 20),
    calc(780, 260, 'P = 12 kN\na = 2.5 m\nb = 3.5 m\nL = a + b\n\nR_B = P*a/L\nR_A = P - R_B\nM_max = R_A*a\nM_max -> kN*m', 'Reactions', 320),
  ]
}

function trussTable(): CanvasElement[] {
  return [
    ...title(40, 100, 'Truss Member Forces', 'METHOD OF JOINTS · RESULTS'),
    underline(42, 146, 320),
    table(40, 200, ['Member', 'Force (kN)', 'T/C', 'Stress (MPa)'], [
      ['AB', '-8.66', 'C', '=B1*1000/450'],
      ['AC', '4.33', 'T', '=B2*1000/450'],
      ['BC', '8.66', 'T', '=B3*1000/450'],
      ['BD', '-4.33', 'C', '=B4*1000/450'],
      ['CD', '-8.66', 'C', '=B5*1000/450'],
      ['max |F|', '=max(abs(B1:B5))', '', ''],
    ], 'Members (A = 450 mm²)'),
    shape('line', 640, 420, 760, 212, { width: 2.6 }),
    shape('line', 760, 212, 880, 420, { width: 2.6 }),
    shape('line', 640, 420, 880, 420, { width: 2.6 }),
    shape('line', 760, 212, 1000, 212, { width: 2.6 }),
    shape('line', 1000, 212, 880, 420, { width: 2.6 }),
    shape('arrow', 1000, 212, 1000, 300, { color: RED, width: 2.6 }),
    eq(1010, 300, '10 kN', 16, RED),
    eq(620, 432, 'A', 16), eq(750, 180, 'B', 16), eq(880, 432, 'C', 16), eq(1006, 180, 'D', 16),
  ]
}

// ═════════════════════════════ Assemble ═════════════════════════════

export function createDemoLibrary(): LibrarySnapshot {
  const physics = build(
    { name: 'Physics II', description: 'Electricity & magnetism — PHYS 2212', icon: 'atom', color: '#ff6b2c', favorite: true, editedAgo: 25 * 60_000 },
    [
      {
        title: 'Electric Fields',
        pages: [
          { title: "Coulomb's Law", elements: coulomb(), openedAgo: 25 * 60_000 },
          { title: 'Field of a Point Charge', elements: pointField(), openedAgo: 3 * 3600_000 },
          { title: "Gauss's Law", template: 'cornell', elements: gauss(), openedAgo: DAY + 3600_000, zoom: 0.85, vpY: 80 },
        ],
      },
      {
        title: 'Electric Potential',
        pages: [
          { title: 'Potential & Work', elements: potential(), openedAgo: 2 * DAY },
          { title: 'Dipole Sketch', template: 'dot', elements: equipotential() },
        ],
      },
      {
        title: 'Capacitance',
        pages: [
          { title: 'Parallel-Plate Capacitor', elements: capacitor(), openedAgo: 5 * 3600_000 },
          { title: 'RC Charging — Lab 4', template: 'graph', elements: rcCharging(), openedAgo: 3 * DAY },
        ],
      },
      { title: 'Circuits', pages: [{ title: "Kirchhoff's Laws", elements: kirchhoff(), openedAgo: 4 * DAY }] },
      {
        title: 'Magnetism',
        pages: [
          { title: 'Lorentz Force', elements: lorentz() },
          { title: 'Long Straight Wire', template: 'dot', elements: biot() },
        ],
      },
    ],
  )

  const calc3 = build(
    { name: 'Calculus III', description: 'Multivariable calculus — MATH 2551', icon: 'integral', color: '#3b82f6', favorite: true, editedAgo: DAY + 2 * 3600_000 },
    [
      {
        title: 'Vectors',
        pages: [
          { title: 'Dot & Cross Products', template: 'graph', elements: dotCross(), openedAgo: DAY + 2 * 3600_000 },
          { title: 'Lines & Planes', template: 'isometric', elements: linesPlanes(), openedAgo: 6 * DAY },
        ],
      },
      {
        title: 'Partial Derivatives',
        pages: [
          { title: 'Partial Derivatives', elements: partials(), openedAgo: 2 * DAY + 3600_000 },
          { title: 'Gradient', template: 'dot', elements: gradient() },
        ],
      },
      {
        title: 'Multiple Integrals',
        pages: [
          { title: 'Double Integrals', template: 'graph', elements: doubleIntegrals() },
          { title: 'Spherical Coordinates', elements: triple() },
        ],
      },
      {
        title: 'Vector Fields',
        pages: [
          { title: 'Rotational Field', template: 'dot', elements: vectorField(), openedAgo: 26 * 3600_000 },
          { title: "Green's Theorem", elements: greens() },
        ],
      },
    ],
  )

  const statics = build(
    { name: 'Statics', description: 'Engineering mechanics — ENGR 2110', icon: 'beam', color: '#14b8a6', favorite: false, editedAgo: 4 * DAY },
    [
      {
        title: 'Equilibrium',
        pages: [
          { title: 'Beam Reactions', elements: beam(), openedAgo: 4 * DAY },
          { title: 'Truss Forces', template: 'graph', elements: trussTable() },
        ],
      },
    ],
  )

  return {
    notebooks: [...physics.notebooks, ...calc3.notebooks, ...statics.notebooks],
    sections: [...physics.sections, ...calc3.sections, ...statics.sections],
    pages: [...physics.pages, ...calc3.pages, ...statics.pages],
  }
}
