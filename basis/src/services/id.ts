export const uid = (prefix = '') =>
  prefix + Date.now().toString(36).slice(-5) + Math.random().toString(36).slice(2, 9)
