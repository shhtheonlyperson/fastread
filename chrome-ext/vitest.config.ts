import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'happy-dom',
    globals: false,
    setupFiles: ['src/test/setup.ts'],
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
    coverage: {
      provider: 'v8',
      include: ['src/lib/**/*.ts', 'src/content/**/*.tsx'],
      exclude: ['**/*.test.ts', '**/*.test.tsx', '**/icons.ts'],
      reporter: ['text', 'lcov'],
    },
  },
});
