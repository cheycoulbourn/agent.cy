-- ============================================
-- agent.cy database schema
-- Run this in Supabase SQL Editor
-- ============================================

-- Enable pgvector for AI embeddings
create extension if not exists vector;

-- ============================================
-- USERS / PROFILES
-- ============================================

-- Brand profiles (extends Supabase auth.users)
create table public.brand_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null unique,
  display_name text not null,
  handle text default '',
  avatar_url text,
  niche text default '',
  sub_niches text[] default '{}',
  voice_adjectives text[] default '{}',
  voice_samples text[] default '{}',
  voice_description text,
  voice_embedding vector(1536),
  target_audience text,
  primary_goal text default 'growAudience',
  weekly_post_target int default 3,
  onboarding_completed boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- CONTENT PILLARS
-- ============================================

create table public.content_pillars (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  description text default '',
  color_hex text default '6C8EBF',
  icon_name text default 'circle.fill',
  target_percentage float default 25.0,
  sort_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- PLATFORM ACCOUNTS
-- ============================================

create type public.social_platform as enum (
  'instagram', 'tiktok', 'youtube', 'pinterest', 'x', 'linkedin', 'facebook'
);

create table public.platform_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  platform social_platform not null,
  handle text default '',
  is_connected boolean default false,
  follower_count int,
  access_token_encrypted text,
  refresh_token_encrypted text,
  token_expires_at timestamptz,
  created_at timestamptz default now()
);

-- ============================================
-- INSPIRATIONS
-- ============================================

create type public.inspiration_source as enum (
  'link', 'image', 'video', 'text', 'screenshot', 'voiceMemo'
);

create table public.inspirations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  source_type inspiration_source not null,
  source_url text,
  source_app text,
  title text,
  notes text,
  media_path text,
  thumbnail_url text,
  voice_memo_path text,
  ai_summary text,
  tags text[] default '{}',
  embedding vector(1536),
  pillar_id uuid references public.content_pillars(id) on delete set null,
  board_id uuid,
  created_at timestamptz default now()
);

create table public.inspiration_boards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  cover_image_path text,
  pillar_id uuid references public.content_pillars(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Add foreign key after board table exists
alter table public.inspirations
  add constraint fk_inspiration_board
  foreign key (board_id) references public.inspiration_boards(id) on delete set null;

-- ============================================
-- CONTENT IDEAS & DRAFTS
-- ============================================

create type public.content_status as enum (
  'captured', 'developing', 'drafted', 'planned', 'scheduled', 'published', 'archived'
);

create type public.content_format as enum (
  'post', 'reel', 'carousel', 'story', 'thread', 'longformVideo', 'shortVideo', 'pin', 'live'
);

create table public.content_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  title text not null,
  caption text,
  hooks text[] default '{}',
  hashtags text[] default '{}',
  notes text,
  status content_status default 'captured',
  format content_format default 'post',
  platforms social_platform[] default '{}',
  media_paths text[] default '{}',
  scheduled_date timestamptz,
  published_date timestamptz,
  collaborators text[] default '{}',
  is_brand_collab boolean default false,
  brand_name text,
  ai_generated boolean default false,
  ai_suggestions text[] default '{}',
  embedding vector(1536),
  pillar_id uuid references public.content_pillars(id) on delete set null,
  inspiration_id uuid references public.inspirations(id) on delete set null,
  brand_deal_id uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- BRAND DEALS
-- ============================================

create type public.deal_status as enum (
  'pitched', 'negotiating', 'contracted', 'inProgress', 'delivered', 'paid', 'declined'
);

create table public.brand_deals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  brand_name text not null,
  contact_name text,
  contact_email text,
  status deal_status default 'pitched',
  payment_amount decimal,
  payment_currency text default 'USD',
  payment_terms text,
  contract_url text,
  notes text,
  start_date date,
  end_date date,
  pillar_id uuid references public.content_pillars(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Add foreign key after brand_deals table exists
alter table public.content_items
  add constraint fk_content_brand_deal
  foreign key (brand_deal_id) references public.brand_deals(id) on delete set null;

-- ============================================
-- CALENDAR EVENTS
-- ============================================

create type public.calendar_event_type as enum (
  'post', 'story', 'reel', 'video', 'dealDeadline', 'meeting', 'other'
);

create table public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  title text not null,
  event_type calendar_event_type default 'post',
  scheduled_at timestamptz not null,
  external_event_id text,
  content_item_id uuid references public.content_items(id) on delete set null,
  brand_deal_id uuid references public.brand_deals(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- AI CONVERSATIONS
-- ============================================

create table public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  context_type text default 'general',
  context_id uuid,
  messages jsonb[] default '{}',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- INDEXES
-- ============================================

create index idx_brand_profiles_user on public.brand_profiles(user_id);
create index idx_content_pillars_user on public.content_pillars(user_id);
create index idx_platform_accounts_user on public.platform_accounts(user_id);
create index idx_inspirations_user on public.inspirations(user_id);
create index idx_inspirations_pillar on public.inspirations(pillar_id);
create index idx_inspiration_boards_user on public.inspiration_boards(user_id);
create index idx_content_items_user on public.content_items(user_id);
create index idx_content_items_status on public.content_items(status);
create index idx_content_items_scheduled on public.content_items(scheduled_date);
create index idx_content_items_pillar on public.content_items(pillar_id);
create index idx_brand_deals_user on public.brand_deals(user_id);
create index idx_brand_deals_status on public.brand_deals(status);
create index idx_calendar_events_user on public.calendar_events(user_id);
create index idx_calendar_events_scheduled on public.calendar_events(scheduled_at);
create index idx_ai_conversations_user on public.ai_conversations(user_id);

-- Vector similarity indexes (for RAG)
create index idx_inspirations_embedding on public.inspirations
  using ivfflat (embedding vector_cosine_ops) with (lists = 100);
create index idx_content_items_embedding on public.content_items
  using ivfflat (embedding vector_cosine_ops) with (lists = 100);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

alter table public.brand_profiles enable row level security;
alter table public.content_pillars enable row level security;
alter table public.platform_accounts enable row level security;
alter table public.inspirations enable row level security;
alter table public.inspiration_boards enable row level security;
alter table public.content_items enable row level security;
alter table public.brand_deals enable row level security;
alter table public.calendar_events enable row level security;
alter table public.ai_conversations enable row level security;

-- Users can only access their own data
create policy "Users can view own data" on public.brand_profiles
  for select using (auth.uid() = user_id);
create policy "Users can insert own data" on public.brand_profiles
  for insert with check (auth.uid() = user_id);
create policy "Users can update own data" on public.brand_profiles
  for update using (auth.uid() = user_id);

create policy "Users can view own pillars" on public.content_pillars
  for select using (auth.uid() = user_id);
create policy "Users can insert own pillars" on public.content_pillars
  for insert with check (auth.uid() = user_id);
create policy "Users can update own pillars" on public.content_pillars
  for update using (auth.uid() = user_id);
create policy "Users can delete own pillars" on public.content_pillars
  for delete using (auth.uid() = user_id);

create policy "Users can view own accounts" on public.platform_accounts
  for select using (auth.uid() = user_id);
create policy "Users can insert own accounts" on public.platform_accounts
  for insert with check (auth.uid() = user_id);
create policy "Users can update own accounts" on public.platform_accounts
  for update using (auth.uid() = user_id);
create policy "Users can delete own accounts" on public.platform_accounts
  for delete using (auth.uid() = user_id);

create policy "Users can view own inspirations" on public.inspirations
  for select using (auth.uid() = user_id);
create policy "Users can insert own inspirations" on public.inspirations
  for insert with check (auth.uid() = user_id);
create policy "Users can update own inspirations" on public.inspirations
  for update using (auth.uid() = user_id);
create policy "Users can delete own inspirations" on public.inspirations
  for delete using (auth.uid() = user_id);

create policy "Users can view own boards" on public.inspiration_boards
  for select using (auth.uid() = user_id);
create policy "Users can insert own boards" on public.inspiration_boards
  for insert with check (auth.uid() = user_id);
create policy "Users can update own boards" on public.inspiration_boards
  for update using (auth.uid() = user_id);
create policy "Users can delete own boards" on public.inspiration_boards
  for delete using (auth.uid() = user_id);

create policy "Users can view own content" on public.content_items
  for select using (auth.uid() = user_id);
create policy "Users can insert own content" on public.content_items
  for insert with check (auth.uid() = user_id);
create policy "Users can update own content" on public.content_items
  for update using (auth.uid() = user_id);
create policy "Users can delete own content" on public.content_items
  for delete using (auth.uid() = user_id);

create policy "Users can view own deals" on public.brand_deals
  for select using (auth.uid() = user_id);
create policy "Users can insert own deals" on public.brand_deals
  for insert with check (auth.uid() = user_id);
create policy "Users can update own deals" on public.brand_deals
  for update using (auth.uid() = user_id);
create policy "Users can delete own deals" on public.brand_deals
  for delete using (auth.uid() = user_id);

create policy "Users can view own events" on public.calendar_events
  for select using (auth.uid() = user_id);
create policy "Users can insert own events" on public.calendar_events
  for insert with check (auth.uid() = user_id);
create policy "Users can update own events" on public.calendar_events
  for update using (auth.uid() = user_id);
create policy "Users can delete own events" on public.calendar_events
  for delete using (auth.uid() = user_id);

create policy "Users can view own conversations" on public.ai_conversations
  for select using (auth.uid() = user_id);
create policy "Users can insert own conversations" on public.ai_conversations
  for insert with check (auth.uid() = user_id);
create policy "Users can update own conversations" on public.ai_conversations
  for update using (auth.uid() = user_id);

-- ============================================
-- AUTO-UPDATE TIMESTAMPS
-- ============================================

create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger set_updated_at before update on public.brand_profiles
  for each row execute function public.handle_updated_at();
create trigger set_updated_at before update on public.content_pillars
  for each row execute function public.handle_updated_at();
create trigger set_updated_at before update on public.content_items
  for each row execute function public.handle_updated_at();
create trigger set_updated_at before update on public.brand_deals
  for each row execute function public.handle_updated_at();
create trigger set_updated_at before update on public.calendar_events
  for each row execute function public.handle_updated_at();
create trigger set_updated_at before update on public.inspiration_boards
  for each row execute function public.handle_updated_at();
create trigger set_updated_at before update on public.ai_conversations
  for each row execute function public.handle_updated_at();
