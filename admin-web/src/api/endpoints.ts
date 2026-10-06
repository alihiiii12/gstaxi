/** نفس الدومين تلقائياً عند فتح اللوحة من gstaxi.online/admin */
function resolveApiBase(): string {
  const fromEnv = import.meta.env.VITE_API_BASE_URL?.replace(/\/$/, '');
  if (fromEnv) {
    // لا تسمح بـ http لـ gstaxi تحت صفحة https (mixed content → Failed to fetch).
    try {
      const u = new URL(fromEnv);
      if (/gstaxi\.online$/i.test(u.hostname) && u.protocol === 'http:') {
        return 'https://gstaxi.online/api';
      }
    } catch {
      /* ignore */
    }
    return fromEnv;
  }
  if (typeof window !== 'undefined' && window.location?.origin) {
    const origin = window.location.origin.replace(/\/$/, '');
    if (/gstaxi\.online$/i.test(new URL(origin).hostname)) {
      return 'https://gstaxi.online/api';
    }
    return `${origin}/api`;
  }
  return 'https://gstaxi.online/api';
}

const base = resolveApiBase();

export const API = {
  base,
  login: `${base}/login`,
  logout: `${base}/logout`,
  currentUser: `${base}/user`,
  updatePassword: `${base}/user/update`,
  dashboardSummary: `${base}/reports/dashboard-summary`,
  dashboardRevenueTrips: `${base}/reports/dashboard-revenue-trips`,
  driversIndex: `${base}/drivers/index`,
  driversStats: `${base}/admin/drivers/stats`,
  driverShow: (id: number) => `${base}/drivers/show/${id}`,
  driversStore: `${base}/drivers/store`,
  driverUpdate: (id: number) => `${base}/drivers/update/${id}`,
  driverDestroy: (id: number) => `${base}/drivers/destroy/${id}`,
  driverSubscriptionRenew: (id: number) =>
    `${base}/admin/drivers/${id}/subscription/renew`,
  driverSubscriptionSetPeriod: (id: number) =>
    `${base}/admin/drivers/${id}/subscription/set-period`,
  driverSubscriptionUnblock: (id: number) =>
    `${base}/admin/drivers/${id}/subscription/unblock`,
  driverSubscriptionBlock: (id: number) =>
    `${base}/admin/drivers/${id}/subscription/block`,
  driverWallet: (id: number) => `${base}/admin/drivers/${id}/wallet`,
  driverWalletReward: (id: number) =>
    `${base}/admin/drivers/${id}/wallet/reward`,
  driverWalletWithdraw: (id: number) =>
    `${base}/admin/drivers/${id}/wallet/withdraw`,
  driverWalletViolation: (id: number) =>
    `${base}/admin/drivers/${id}/wallet/violation`,
  carTypesIndex: `${base}/car-types/index`,
  carTypesStore: `${base}/car-types/store`,
  carTypesUpdate: `${base}/car-types/update`,
  carTypesDestroy: (id: number) => `${base}/car-types/destroy/${id}`,
  discountsIndex: `${base}/discounts/index`,
  discountsStore: `${base}/discounts/store`,
  discountsDestroy: (id: number) => `${base}/discounts/destroy/${id}`,
  discountsUpdate: (id: number) => `${base}/discounts/update/${id}`,
  emergencyActive: `${base}/emergency/active`,
  clearSos: (key: string | number) =>
    `${base}/emergency/active/${encodeURIComponent(String(key))}`,
  sosLive: (key: string | number) =>
    `${base}/emergency/live/${encodeURIComponent(String(key))}`,
  adminRequests: `${base}/admin/requests`,
  adminRequestDetail: (id: number) => `${base}/admin/requests/${id}`,
  adminDispatchToDriver: `${base}/admin/requests/dispatch-to-driver`,
  adminExpirePending: (id: number) => `${base}/admin/requests/${id}/expire-pending`,
  adminCancelActive: (id: number) => `${base}/admin/requests/${id}/cancel-active`,
  adminCustomers: `${base}/admin/customers`,
  adminCustomerDestroy: (id: number) => `${base}/admin/customers/${id}`,
  customerWallet: (id: number) => `${base}/admin/customers/${id}/wallet`,
  customerWalletsLog: `${base}/admin/customer-wallets/log`,
  customerWalletTopup: (id: number) => `${base}/admin/customers/${id}/wallet/topup`,
  customerWalletDeduct: (id: number) => `${base}/admin/customers/${id}/wallet/deduct`,
  customerWalletAdjust: (id: number) => `${base}/admin/customers/${id}/wallet/adjust`,
  adminWhatsAppBroadcast: `${base}/admin/whatsapp-broadcast`,
  adminWhatsAppBroadcastRecipients: `${base}/admin/whatsapp-broadcast/recipients-count`,
  adminWhatsAppBroadcastLast: `${base}/admin/whatsapp-broadcast/last`,
  adminWhatsAppBroadcastStatus: (id: string) =>
    `${base}/admin/whatsapp-broadcast/${encodeURIComponent(id)}/status`,
  adminWhatsAppBroadcastCancel: (id: string) =>
    `${base}/admin/whatsapp-broadcast/${encodeURIComponent(id)}/cancel`,
  adminWhatsAppBroadcastResetBatch: `${base}/admin/whatsapp-broadcast/reset-batch`,
  adminAppUpdateSettings: `${base}/admin/app-update-settings`,
  adminComplaintsReviews: `${base}/admin/complaints-reviews`,
  adminEmployees: `${base}/admin/employees`,
  adminEmployeeDestroy: (id: number) => `${base}/admin/employees/${id}`,
  adminEmployeePermissions: (userId: number) =>
    `${base}/admin/employees/${userId}/permissions`,
  adminServiceAreas: `${base}/admin/service-areas`,
  adminServiceAreaUpdate: (id: number) => `${base}/admin/service-areas/${id}`,
  adminFreeMeterSettings: `${base}/admin/free-meter-settings`,
  adminPricingZones: `${base}/admin/pricing-zones`,
  adminPricingZone: (id: number) => `${base}/admin/pricing-zones/${id}`,
  adminPricingZoneRules: `${base}/admin/pricing-zones/rules`,
  adminPricingZoneOutside: `${base}/admin/pricing-zones/outside`,
  adminPricingZoneQuote: `${base}/admin/pricing-zones/quote`,
  adminMapSnapshot: `${base}/admin/map-snapshot`,
  adminCustomersMapSnapshot: `${base}/admin/customers-map-snapshot`,
  adminMtnSmsBroadcast: `${base}/admin/mtn-sms-broadcast`,
  adminMtnSmsBroadcastRecipients: `${base}/admin/mtn-sms-broadcast/recipients-count`,
  adminMtnSmsBroadcastLast: `${base}/admin/mtn-sms-broadcast/last`,
  adminMtnSmsBroadcastStatus: (id: string) =>
    `${base}/admin/mtn-sms-broadcast/${encodeURIComponent(id)}/status`,
  adminMtnSmsBroadcastCancel: (id: string) =>
    `${base}/admin/mtn-sms-broadcast/${encodeURIComponent(id)}/cancel`,
  adminMtnSmsBroadcastResetBatch: `${base}/admin/mtn-sms-broadcast/reset-batch`,
  adminRunningTripLive: (id: number) => `${base}/admin/running-trips/${id}/live`,
  adminRunningTripLiveStream: (id: number) =>
    `${base}/admin/running-trips/${id}/live-stream`,
  adminDriverTrips: (id: number) => `${base}/admin/drivers/${id}/trips`,
  drivingSummary: `${base}/routing/driving-summary`,
  adminExportUsersCsv: `${base}/admin/export-users.csv`,
  financialReport: (fromDate: string, toDate: string, format: string) =>
    `${base}/reports/financial?from_date=${encodeURIComponent(fromDate)}&to_date=${encodeURIComponent(toDate)}&format=${format}`,
  adminDiscountNotify: (discountId: number) =>
    `${base}/admin/discounts/${discountId}/notify-customers`,
  adminPlacesSearch: `${base}/admin/places/search`,
  adminPlacesReverse: `${base}/admin/places/reverse`,
};
