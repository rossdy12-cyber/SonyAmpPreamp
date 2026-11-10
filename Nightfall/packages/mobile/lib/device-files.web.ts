import type { Download } from './browser';
export async function downloadFile(_url: string): Promise<Download> { throw new Error('File downloads are available in the installed iPhone app, not this preview.'); }
export async function shareFile(_uri: string) { throw new Error('Native file sharing is available in the installed iPhone app.'); }
export async function deleteFile(_uri: string) {}