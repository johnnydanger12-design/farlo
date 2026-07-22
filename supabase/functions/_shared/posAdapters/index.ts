import type { PosAdapter } from './types.ts';
import { cloverAdapter } from './clover.ts';
import { squareAdapter } from './square.ts';

export function getAdapter(provider: string): PosAdapter {
  switch (provider) {
    case 'clover':
      return cloverAdapter;
    case 'square':
      return squareAdapter;
    default:
      throw new Error(`No POS adapter for provider: ${provider}`);
  }
}

export type { PosAdapter, PosCredentials, PosOrder, PosOrderItem } from './types.ts';
