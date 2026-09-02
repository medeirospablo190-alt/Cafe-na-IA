export type App1Role = "ADM" | "DEV";
export type AccountStatus = "ACTIVE" | "SUSPENDED" | "DELETED";

export const APP1_ROLES: Readonly<{ ADM: "ADM"; DEV: "DEV" }>;
export const ACCOUNT_STATUS: Readonly<{
  ACTIVE: "ACTIVE";
  SUSPENDED: "SUSPENDED";
  DELETED: "DELETED";
}>;

export const APP1_CREDENTIAL_POLICY: Readonly<{
  ADM_CHARS: 256;
  DEV_CHARS: 600;
  SESSION_HOURS: 12;
}>;

export const APP1_PERMISSIONS: Readonly<{
  SESSION_USE: "app1.session.use";
  ADMIN_AREA: "app1.admin";
  DEV_PRIVILEGED: "app1.dev.privileged";
  SOCIAL_PIN_POST: "app1.social.pin-post";
}>;

export type App1Permission = typeof APP1_PERMISSIONS[keyof typeof APP1_PERMISSIONS];

export const APP1_ROLE_PERMISSIONS: Readonly<Record<App1Role, readonly App1Permission[]>>;
export function permissionsForRole(role: string | null | undefined): readonly App1Permission[];
export function roleHasPermission(role: string | null | undefined, permission: string): boolean;

export const KEYMASTER: Readonly<{
  MAX_KEY_CHARS: 16384;
  DEFAULT_ACCESS_KEY_CHARS: 5000;
  MAX_FAILED_ATTEMPTS: 3;
  LOCK_HOURS: 24;
  CRITICAL_AUTH_MINUTES: 2;
}>;

export const CRITICAL_ACTIONS: Readonly<{
  APP1_RESTART: "APP1_RESTART";
  APP1_MAINTENANCE_ON: "APP1_MAINTENANCE_ON";
  APP1_MAINTENANCE_OFF: "APP1_MAINTENANCE_OFF";
  DELETE_APP1_ACCOUNT: "DELETE_APP1_ACCOUNT";
  DELETE_MANAGED_MENU: "DELETE_MANAGED_MENU";
}>;

export const API_ERRORS: Readonly<Record<string, string>>;
