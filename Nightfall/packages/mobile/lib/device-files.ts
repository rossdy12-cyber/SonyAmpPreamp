import * as FileSystem from 'expo-file-system/legacy';
import * as Sharing from 'expo-sharing';
import type { Download } from './browser';
import { makeId } from './browser';
export async function downloadFile(url: string): Promise<Download> {
  const parsed = new URL(url);
  if (!['http:', 'https:'].includes(parsed.protocol)) throw new Error('Only HTTP and HTTPS downloads are supported.');
  const id = makeId();
  const raw = decodeURIComponent(parsed.pathname.split('/').pop() || 'download');
  const name = raw.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 100) || 'download';
  const folder = `${FileSystem.documentDirectory}downloads/`;
  await FileSystem.makeDirectoryAsync(folder, { intermediates: true });
  const uri = folder + id + '-' + name;
  const result = await FileSystem.downloadAsync(url, uri);
  if (result.status >= 400) { await FileSystem.deleteAsync(uri, { idempotent: true }); throw new Error(`Download failed (HTTP ${result.status}). Files requiring website cookies may need Safari.`); }
  return { id, name, uri: result.uri, date: Date.now() };
}
export async function shareFile(uri: string) { if (!(await Sharing.isAvailableAsync())) throw new Error('File sharing is not available.'); await Sharing.shareAsync(uri); }
export async function deleteFile(uri: string) { await FileSystem.deleteAsync(uri, { idempotent: true }); }