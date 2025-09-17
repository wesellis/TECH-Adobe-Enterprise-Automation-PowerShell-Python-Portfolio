module.exports = {
  testEnvironment: 'node',
  rootDir: '..',
  coverageDirectory: '<rootDir>/coverage',
  collectCoverageFrom: [
    '<rootDir>/api/**/*.js',
    '<rootDir>/modules/**/*.js',
    '!**/node_modules/**',
    '!**/dist/**',
    '!**/coverage/**',
    '!**/*.config.js'
  ],
  coverageThreshold: {
    global: {
      branches: 40,
      functions: 40,
      lines: 40,
      statements: 40
    }
  },
  testMatch: [
    '<rootDir>/**/__tests__/**/*.js',
    '<rootDir>/**/?(*.)+(spec|test).js',
    '<rootDir>/tests/**/*.test.js',
    '<rootDir>/api/**/*.test.js'
  ],
  testPathIgnorePatterns: [
    '/node_modules/',
    '/dist/',
    '/build/'
  ],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/$1',
    '^@api/(.*)$': '<rootDir>/api/$1',
    '^@config/(.*)$': '<rootDir>/config/$1',
    '^@modules/(.*)$': '<rootDir>/modules/$1'
  },
  setupFilesAfterEnv: [],
  verbose: true,
  bail: false,
  maxWorkers: '50%',
  reporters: [
    'default',
    ['jest-junit', {
      outputDirectory: 'reports',
      outputName: 'junit.xml',
      ancestorSeparator: ' › ',
      uniqueOutputName: 'false',
      suiteNameTemplate: '{filepath}',
      classNameTemplate: '{classname}',
      titleTemplate: '{title}'
    }]
  ],
  coverageReporters: [
    'json',
    'lcov',
    'text',
    'html',
    'cobertura'
  ],
  globals: {
    'NODE_ENV': 'test'
  }
};