-- =====================================================================
-- VIBEITY backend, phase 1: database, security rules (RLS) and storage
-- Run once in: Supabase dashboard -> SQL Editor -> New query -> paste -> Run
-- Safe to re-run: it uses "if not exists", "or replace" and "drop policy if exists".
-- NEVER put your service_role key in index.html. Only the anon/publishable key.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------

-- 1.1 profiles (one row per signed-up user, id = auth user id)
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text,
  username    text,
  gender      text,
  intent      text check (intent in ('relationship','friendship')),
  profession  text,
  state       text,
  city        text,
  bio         text check (char_length(bio) <= 300),
  photo_url   text,
  privacy     text not null default 'public' check (privacy in ('public','private')),
  verified    boolean not null default false,
  onboarded   boolean not null default false,
  prefs       jsonb not null default '{"matches":true,"messages":true,"likes":true}',
  last_seen_at timestamptz,
  created_at  timestamptz not null default now(),
  constraint username_format check (username is null or username ~ '^[a-z0-9._]{3,30}$')
);
create unique index if not exists profiles_username_key on public.profiles (lower(username));

-- 1.2 friendships (created automatically when two people like each other)
create table if not exists public.friendships (
  user_a     uuid not null references public.profiles(id) on delete cascade,
  user_b     uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index if not exists friendships_b_idx on public.friendships (user_b);

-- 1.3 swipes (right swipe = like, star = super, left swipe = pass)
create table if not exists public.swipes (
  from_user  uuid not null references public.profiles(id) on delete cascade,
  to_user    uuid not null references public.profiles(id) on delete cascade,
  action     text not null check (action in ('like','super','pass')),
  created_at timestamptz not null default now(),
  primary key (from_user, to_user),
  check (from_user <> to_user)
);
create index if not exists swipes_to_idx on public.swipes (to_user, action);

-- 1.4 posts
create table if not exists public.posts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  body        text check (char_length(body) <= 1500),
  media_url   text,
  media_type  text check (media_type in ('image','video')),
  shared_from uuid references public.profiles(id) on delete set null,
  shared_post uuid references public.posts(id) on delete set null,
  created_at  timestamptz not null default now(),
  constraint post_has_content check (body is not null or media_url is not null)
);
create index if not exists posts_user_idx on public.posts (user_id, created_at desc);
create index if not exists posts_created_idx on public.posts (created_at desc);

create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create table if not exists public.post_saves (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create table if not exists public.post_shares (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create table if not exists public.post_views (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- 1.5 comments (replies use parent_id) and their likes / saves / shares
create table if not exists public.comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  parent_id  uuid references public.comments(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists comments_post_idx on public.comments (post_id, created_at desc);

create table if not exists public.comment_likes (
  comment_id uuid not null references public.comments(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
create table if not exists public.comment_saves (
  comment_id uuid not null references public.comments(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
create table if not exists public.comment_shares (
  comment_id uuid not null references public.comments(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

-- 1.6 one-to-one chats between friends
create table if not exists public.conversations (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  last_read_at    timestamptz not null default now(),
  pinned          boolean not null default false,
  primary key (conversation_id, user_id)
);
create index if not exists conv_members_user_idx on public.conversation_members (user_id);
create table if not exists public.messages (
  id              bigint generated always as identity primary key,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id       uuid not null references public.profiles(id) on delete cascade,
  body            text not null check (char_length(body) between 1 and 1000),
  shared_post_id  uuid references public.posts(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists messages_conv_idx on public.messages (conversation_id, created_at);

-- 1.7 communities (groups) and their chat
create table if not exists public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 3 and 40),
  description text check (char_length(description) <= 140),
  emoji       text not null default '👥',
  created_by  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now()
);
create table if not exists public.group_members (
  group_id  uuid not null references public.groups(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists group_members_user_idx on public.group_members (user_id);
create table if not exists public.group_messages (
  id        bigint generated always as identity primary key,
  group_id  uuid not null references public.groups(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body      text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists group_messages_idx on public.group_messages (group_id, created_at);

-- ---------------------------------------------------------------------
-- 2. HELPER FUNCTIONS (they run with owner rights so rules never loop)
-- ---------------------------------------------------------------------

create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.friendships f
                 where f.user_a = least(a, b) and f.user_b = greatest(a, b));
$$;

-- public accounts: everyone; private accounts: only the owner and friends
create or replace function public.can_view_profile(target uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select target = auth.uid()
      or exists (select 1 from public.profiles p where p.id = target and p.privacy = 'public')
      or public.are_friends(auth.uid(), target);
$$;

create or replace function public.is_conversation_member(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.conversation_members m
                 where m.conversation_id = cid and m.user_id = auth.uid());
$$;

create or replace function public.is_group_member(gid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.group_members m
                 where m.group_id = gid and m.user_id = auth.uid());
$$;

create or replace function public.friend_count(uid uuid)
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from public.friendships f where uid in (f.user_a, f.user_b);
$$;

-- ---------------------------------------------------------------------
-- 3. TRIGGERS
-- ---------------------------------------------------------------------

-- 3.1 create a profile row when someone signs up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 3.2 users can not make themselves "verified"
create or replace function public.protect_profile_columns()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.verified := old.verified;
    new.id := old.id;
  end if;
  return new;
end $$;
drop trigger if exists protect_profile on public.profiles;
create trigger protect_profile before update on public.profiles
  for each row execute function public.protect_profile_columns();

-- 3.3 two likes = a match = friendship
create or replace function public.handle_swipe()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.action in ('like', 'super') and exists (
       select 1 from public.swipes s
       where s.from_user = new.to_user and s.to_user = new.from_user
         and s.action in ('like', 'super')) then
    insert into public.friendships (user_a, user_b)
    values (least(new.from_user, new.to_user), greatest(new.from_user, new.to_user))
    on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists on_swipe on public.swipes;
create trigger on_swipe after insert or update on public.swipes
  for each row execute function public.handle_swipe();

-- 3.4 the creator of a group joins it automatically
create or replace function public.handle_new_group()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.group_members (group_id, user_id) values (new.id, new.created_by)
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_group_created on public.groups;
create trigger on_group_created after insert on public.groups
  for each row execute function public.handle_new_group();

-- ---------------------------------------------------------------------
-- 4. VIEWS (what the app reads: counts only, never who liked/saved/shared)
-- ---------------------------------------------------------------------

-- 4.1 safe public profile data (private accounts hide their details)
create or replace view public.public_profiles as
select p.id, p.name, p.username, p.photo_url, p.verified, p.intent, p.privacy,
       case when public.can_view_profile(p.id) then p.profession end as profession,
       case when public.can_view_profile(p.id) then p.state end      as state,
       case when public.can_view_profile(p.id) then p.city end       as city,
       case when public.can_view_profile(p.id) then p.bio end        as bio,
       (p.last_seen_at is not null and p.last_seen_at > now() - interval '2 minutes') as online,
       p.created_at
from public.profiles p
where p.onboarded or p.id = auth.uid();

-- 4.2 posts with counts (only posts the viewer is allowed to see)
create or replace view public.feed_posts as
select p.id, p.user_id, p.body, p.media_url, p.media_type, p.shared_from, p.shared_post, p.created_at,
       (select count(*) from public.post_likes  x where x.post_id = p.id)::int as likes_count,
       (select count(*) from public.post_saves  x where x.post_id = p.id)::int as saves_count,
       (select count(*) from public.post_shares x where x.post_id = p.id)::int as shares_count,
       (select count(*) from public.comments    x where x.post_id = p.id)::int as comments_count,
       exists (select 1 from public.post_likes  x where x.post_id = p.id and x.user_id = auth.uid()) as liked_by_me,
       exists (select 1 from public.post_saves  x where x.post_id = p.id and x.user_id = auth.uid()) as saved_by_me,
       exists (select 1 from public.post_shares x where x.post_id = p.id and x.user_id = auth.uid()) as shared_by_me,
       exists (select 1 from public.comments    x where x.post_id = p.id and x.user_id = auth.uid()) as commented_by_me
from public.posts p
where public.can_view_profile(p.user_id);

-- 4.3 comments with like counts
create or replace view public.comments_with_counts as
select c.id, c.post_id, c.user_id, c.parent_id, c.body, c.created_at,
       (select count(*) from public.comment_likes x where x.comment_id = c.id)::int as likes_count,
       exists (select 1 from public.comment_likes x where x.comment_id = c.id and x.user_id = auth.uid()) as liked_by_me,
       exists (select 1 from public.comment_saves x where x.comment_id = c.id and x.user_id = auth.uid()) as saved_by_me
from public.comments c
where exists (select 1 from public.posts p where p.id = c.post_id and public.can_view_profile(p.user_id));

-- 4.4 who liked me (the "Requests" tab). Sent likes are never shown to anyone.
create or replace view public.incoming_likes as
select s.from_user as user_id, (s.action = 'super') as super, s.created_at
from public.swipes s
where s.to_user = auth.uid()
  and s.action in ('like', 'super')
  and not public.are_friends(auth.uid(), s.from_user)
  and not exists (select 1 from public.swipes mine
                  where mine.from_user = auth.uid() and mine.to_user = s.from_user);

-- 4.5 my friends
create or replace view public.my_friends as
select case when f.user_a = auth.uid() then f.user_b else f.user_a end as friend_id, f.created_at
from public.friendships f
where auth.uid() in (f.user_a, f.user_b);

-- 4.6 groups with member counts (member names stay private)
create or replace view public.groups_with_counts as
select g.id, g.name, g.description, g.emoji, g.created_by, g.created_at,
       (select count(*) from public.group_members m where m.group_id = g.id)::int as member_count,
       exists (select 1 from public.group_members m where m.group_id = g.id and m.user_id = auth.uid()) as joined
from public.groups g;

-- ---------------------------------------------------------------------
-- 5. FUNCTIONS THE APP CALLS (supabase.rpc)
-- ---------------------------------------------------------------------

-- people to swipe on: not me, not friends, not already swiped; people who liked me come first
create or replace function public.get_discover(p_limit integer default 20)
returns setof public.public_profiles language sql stable security definer set search_path = public as $$
  select pp.*
  from public.public_profiles pp
  where pp.id <> auth.uid()
    and not public.are_friends(auth.uid(), pp.id)
    and not exists (select 1 from public.swipes s where s.from_user = auth.uid() and s.to_user = pp.id)
  order by exists (select 1 from public.swipes s2
                   where s2.from_user = pp.id and s2.to_user = auth.uid()
                     and s2.action in ('like', 'super')) desc,
           random()
  limit greatest(1, least(p_limit, 50));
$$;

-- "For You" feed: posts I can see and have not viewed yet, in random order
create or replace function public.get_feed(p_limit integer default 20)
returns setof public.feed_posts language sql stable security definer set search_path = public as $$
  select f.*
  from public.feed_posts f
  where not exists (select 1 from public.post_views v
                    where v.post_id = f.id and v.user_id = auth.uid())
  order by random()
  limit greatest(1, least(p_limit, 50));
$$;

-- "Watch again from the start"
create or replace function public.reset_seen()
returns void language sql security definer set search_path = public as $$
  delete from public.post_views where user_id = auth.uid();
$$;

-- open (or create) a chat with a friend, returns the conversation id
create or replace function public.start_chat(other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me  uuid := auth.uid();
  cid uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.are_friends(me, other) then raise exception 'you can only message friends'; end if;
  select a.conversation_id into cid
  from public.conversation_members a
  join public.conversation_members b on b.conversation_id = a.conversation_id
  where a.user_id = me and b.user_id = other
  limit 1;
  if cid is null then
    insert into public.conversations default values returning id into cid;
    insert into public.conversation_members (conversation_id, user_id) values (cid, me), (cid, other);
  end if;
  return cid;
end $$;

-- ---------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY (who can read / write what)
-- ---------------------------------------------------------------------

alter table public.profiles             enable row level security;
alter table public.friendships          enable row level security;
alter table public.swipes               enable row level security;
alter table public.posts                enable row level security;
alter table public.post_likes           enable row level security;
alter table public.post_saves           enable row level security;
alter table public.post_shares          enable row level security;
alter table public.post_views           enable row level security;
alter table public.comments             enable row level security;
alter table public.comment_likes        enable row level security;
alter table public.comment_saves        enable row level security;
alter table public.comment_shares       enable row level security;
alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;
alter table public.groups               enable row level security;
alter table public.group_members        enable row level security;
alter table public.group_messages       enable row level security;

-- profiles: you only touch your own row; others are read through public_profiles
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles for insert to authenticated with check (id = auth.uid());
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- friendships: members can see and end their own friendships (creation is automatic)
drop policy if exists "friendships_select" on public.friendships;
create policy "friendships_select" on public.friendships for select to authenticated using (auth.uid() in (user_a, user_b));
drop policy if exists "friendships_delete" on public.friendships;
create policy "friendships_delete" on public.friendships for delete to authenticated using (auth.uid() in (user_a, user_b));

-- swipes: you see your own swipes and likes sent TO you; nobody sees who you passed
drop policy if exists "swipes_select" on public.swipes;
create policy "swipes_select" on public.swipes for select to authenticated
  using (from_user = auth.uid() or (to_user = auth.uid() and action in ('like', 'super')));
drop policy if exists "swipes_insert" on public.swipes;
create policy "swipes_insert" on public.swipes for insert to authenticated with check (from_user = auth.uid());
drop policy if exists "swipes_update" on public.swipes;
create policy "swipes_update" on public.swipes for update to authenticated using (from_user = auth.uid()) with check (from_user = auth.uid());
drop policy if exists "swipes_delete" on public.swipes;
create policy "swipes_delete" on public.swipes for delete to authenticated using (from_user = auth.uid());

-- posts: public accounts are visible to everyone, private ones only to friends
drop policy if exists "posts_select" on public.posts;
create policy "posts_select" on public.posts for select to authenticated using (public.can_view_profile(user_id));
drop policy if exists "posts_insert" on public.posts;
create policy "posts_insert" on public.posts for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "posts_update" on public.posts;
create policy "posts_update" on public.posts for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "posts_delete" on public.posts;
create policy "posts_delete" on public.posts for delete to authenticated using (user_id = auth.uid());

-- likes / saves / shares / views: you only see your own rows (the app shows numbers via feed_posts)
do $$
declare t text;
begin
  foreach t in array array['post_likes','post_saves','post_shares','post_views'] loop
    execute format('drop policy if exists "%1$s_select" on public.%1$s', t);
    execute format('create policy "%1$s_select" on public.%1$s for select to authenticated using (user_id = auth.uid())', t);
    execute format('drop policy if exists "%1$s_insert" on public.%1$s', t);
    execute format('create policy "%1$s_insert" on public.%1$s for insert to authenticated with check (user_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id))', t);
    execute format('drop policy if exists "%1$s_delete" on public.%1$s', t);
    execute format('create policy "%1$s_delete" on public.%1$s for delete to authenticated using (user_id = auth.uid())', t);
  end loop;
end $$;

-- comments: readable when the post is readable
drop policy if exists "comments_select" on public.comments;
create policy "comments_select" on public.comments for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id));
drop policy if exists "comments_insert" on public.comments;
create policy "comments_insert" on public.comments for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id));
drop policy if exists "comments_delete" on public.comments;
create policy "comments_delete" on public.comments for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from public.posts p where p.id = post_id and p.user_id = auth.uid()));

do $$
declare t text;
begin
  foreach t in array array['comment_likes','comment_saves','comment_shares'] loop
    execute format('drop policy if exists "%1$s_select" on public.%1$s', t);
    execute format('create policy "%1$s_select" on public.%1$s for select to authenticated using (user_id = auth.uid())', t);
    execute format('drop policy if exists "%1$s_insert" on public.%1$s', t);
    execute format('create policy "%1$s_insert" on public.%1$s for insert to authenticated with check (user_id = auth.uid() and exists (select 1 from public.comments c where c.id = comment_id))', t);
    execute format('drop policy if exists "%1$s_delete" on public.%1$s', t);
    execute format('create policy "%1$s_delete" on public.%1$s for delete to authenticated using (user_id = auth.uid())', t);
  end loop;
end $$;

-- chats: only the two people in a conversation can read or write it
drop policy if exists "conversations_select" on public.conversations;
create policy "conversations_select" on public.conversations for select to authenticated using (public.is_conversation_member(id));
drop policy if exists "conv_members_select" on public.conversation_members;
create policy "conv_members_select" on public.conversation_members for select to authenticated using (public.is_conversation_member(conversation_id));
drop policy if exists "conv_members_update_own" on public.conversation_members;
create policy "conv_members_update_own" on public.conversation_members for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "messages_select" on public.messages;
create policy "messages_select" on public.messages for select to authenticated using (public.is_conversation_member(conversation_id));
drop policy if exists "messages_insert" on public.messages;
create policy "messages_insert" on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_conversation_member(conversation_id));

-- groups: anyone signed in can discover groups; only members read the group chat
drop policy if exists "groups_select" on public.groups;
create policy "groups_select" on public.groups for select to authenticated using (true);
drop policy if exists "groups_insert" on public.groups;
create policy "groups_insert" on public.groups for insert to authenticated with check (created_by = auth.uid());
drop policy if exists "groups_update" on public.groups;
create policy "groups_update" on public.groups for update to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid());
drop policy if exists "groups_delete" on public.groups;
create policy "groups_delete" on public.groups for delete to authenticated using (created_by = auth.uid());
drop policy if exists "group_members_select" on public.group_members;
create policy "group_members_select" on public.group_members for select to authenticated using (user_id = auth.uid());
drop policy if exists "group_members_join" on public.group_members;
create policy "group_members_join" on public.group_members for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "group_members_leave" on public.group_members;
create policy "group_members_leave" on public.group_members for delete to authenticated using (user_id = auth.uid());
drop policy if exists "group_messages_select" on public.group_messages;
create policy "group_messages_select" on public.group_messages for select to authenticated using (public.is_group_member(group_id));
drop policy if exists "group_messages_insert" on public.group_messages;
create policy "group_messages_insert" on public.group_messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_group_member(group_id));

-- ---------------------------------------------------------------------
-- 7. WHO MAY CALL WHAT
-- ---------------------------------------------------------------------
revoke all on public.public_profiles, public.feed_posts, public.comments_with_counts,
              public.incoming_likes, public.my_friends, public.groups_with_counts from anon;
grant select on public.public_profiles, public.feed_posts, public.comments_with_counts,
                public.incoming_likes, public.my_friends, public.groups_with_counts to authenticated;
revoke execute on function public.get_discover(integer), public.get_feed(integer),
                           public.reset_seen(), public.start_chat(uuid), public.friend_count(uuid) from anon, public;
grant execute on function public.get_discover(integer), public.get_feed(integer),
                          public.reset_seen(), public.start_chat(uuid), public.friend_count(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 8. FILE STORAGE (profile photos and post photos/videos)
-- Files go in a folder named after the user id:  <user-id>/<file-name>
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit) values ('posts', 'posts', true, 52428800)
  on conflict (id) do nothing;

do $$
declare b text;
begin
  foreach b in array array['avatars','posts'] loop
    execute format('drop policy if exists "%1$s_read" on storage.objects', b);
    execute format('create policy "%1$s_read" on storage.objects for select using (bucket_id = %2$L)', b, b);
    execute format('drop policy if exists "%1$s_write_own" on storage.objects', b);
    execute format('create policy "%1$s_write_own" on storage.objects for insert to authenticated with check (bucket_id = %2$L and (storage.foldername(name))[1] = auth.uid()::text)', b, b);
    execute format('drop policy if exists "%1$s_update_own" on storage.objects', b);
    execute format('create policy "%1$s_update_own" on storage.objects for update to authenticated using (bucket_id = %2$L and (storage.foldername(name))[1] = auth.uid()::text)', b, b);
    execute format('drop policy if exists "%1$s_delete_own" on storage.objects', b);
    execute format('create policy "%1$s_delete_own" on storage.objects for delete to authenticated using (bucket_id = %2$L and (storage.foldername(name))[1] = auth.uid()::text)', b, b);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 9. REALTIME (new chat messages appear instantly)
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'group_messages') then
    alter publication supabase_realtime add table public.group_messages;
  end if;
end $$;

-- done. Next: paste your Project URL and anon key into index.html (see BACKEND_SETUP.md).
