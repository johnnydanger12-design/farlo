// Mirrors the subset of food_trucks/operating_hours/menu_items columns this
// page actually renders. See lib/features/map/models/food_truck.dart,
// lib/features/food_trucks/models/operating_hours.dart, and
// lib/features/food_trucks/models/menu_item.dart for the Flutter-side
// source of truth this is kept in sync with.

export interface OperatingHours {
  day_of_week: number; // 0 = Sunday ... 6 = Saturday
  open_time: string | null; // "HH:MM:SS"
  close_time: string | null;
  is_closed: boolean;
}

export interface MenuItem {
  id: string;
  name: string;
  description: string | null;
  price: number;
  image_url: string | null;
  category: string;
  is_available: boolean;
  sort_order: number;
}

export interface FoodTruck {
  id: string;
  name: string;
  slug: string;
  cuisine_type: string;
  description: string | null;
  logo_url: string | null;
  photo_urls: string[];
  menu_pdf_url: string | null;
  menu_image_url: string | null;
  average_rating: number;
  review_count: number;
  is_open: boolean;
  address: string | null;
  business_type: string;
  social_instagram: string | null;
  social_tiktok: string | null;
  social_facebook: string | null;
  social_twitter: string | null;
  social_youtube: string | null;
  website_url: string | null;
  operating_hours: OperatingHours[];
  menu_items: MenuItem[];
}
