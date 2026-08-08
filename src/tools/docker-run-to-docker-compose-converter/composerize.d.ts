declare module 'composerize' {
  type ComposeVersion = 'v2x' | 'v3x' | 'latest';
  const composerize: (
    dockerRunCommand: string,
    existingComposeFile?: string,
    composeVersion?: ComposeVersion,
    indent?: number,
  ) => string;
  export default composerize;
}
