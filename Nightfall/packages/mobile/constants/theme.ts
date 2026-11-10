import { palette } from '../lib/browser';
const theme = {
  background: palette.bg, foreground: palette.text, card: palette.panel,
  cardForeground: palette.text, primary: palette.gold, primaryForeground: palette.bg,
  secondary: palette.raised, secondaryForeground: palette.text, muted: palette.raised,
  mutedForeground: palette.muted, accent: palette.wine, accentForeground: palette.text,
  border: palette.border, destructive: '#D57979', success: '#93B79C', warning: palette.gold,
} as const;
export const Colors = { light: theme, dark: theme } as const;
export type ColorScheme = keyof typeof Colors;
export type ThemeColors = typeof theme;
export const Fonts = { sans: 'Inter_400Regular', serif: 'Cinzel_400Regular', rounded: 'Inter_500Medium', mono: 'monospace' };