import { ClearBrowsingDataResult, PrivacyManager } from './privacyManager';

export interface PrivateSessionCleaner {
  clearPrivateSessionData(): ClearBrowsingDataResult;
}

export class PrivateSessionCoordinator {
  private static instance: PrivateSessionCoordinator = new PrivateSessionCoordinator();
  private readonly activeOwners: Set<string> = new Set();
  private readonly cleaner: PrivateSessionCleaner;
  private nextOwnerIndex: number = 0;

  constructor(cleaner?: PrivateSessionCleaner) {
    this.cleaner = cleaner ?? PrivacyManager.getInstance();
  }

  static getInstance(): PrivateSessionCoordinator {
    return PrivateSessionCoordinator.instance;
  }

  createOwnerId(prefix: string): string {
    const normalizedPrefix = prefix.trim().length > 0 ? prefix.trim() : 'private-session';
    const ownerId = `${normalizedPrefix}_${Date.now()}_${this.nextOwnerIndex}`;
    this.nextOwnerIndex += 1;
    return ownerId;
  }

  acquire(ownerId: string): boolean {
    const normalizedOwnerId = ownerId.trim();
    if (!normalizedOwnerId || this.activeOwners.has(normalizedOwnerId)) {
      return false;
    }
    this.activeOwners.add(normalizedOwnerId);
    return true;
  }

  release(ownerId: string): ClearBrowsingDataResult | null {
    const normalizedOwnerId = ownerId.trim();
    if (!normalizedOwnerId || !this.activeOwners.delete(normalizedOwnerId)) {
      return null;
    }
    if (this.activeOwners.size > 0) {
      return null;
    }
    return this.cleaner.clearPrivateSessionData();
  }

  hasOwner(ownerId: string): boolean {
    return this.activeOwners.has(ownerId.trim());
  }

  getActiveOwnerCount(): number {
    return this.activeOwners.size;
  }
}
