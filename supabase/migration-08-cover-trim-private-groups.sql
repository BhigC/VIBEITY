-- Applied to project obzmukyyfxxtqufabjjz (record of what was run). Safe to re-run.
alter table public.profiles add column if not exists cover_url text;       -- profile cover photo (public_profiles view exposes it)
alter table public.posts add column if not exists trim_start numeric;      -- video trim: the original file is kept,
alter table public.posts add column if not exists trim_end numeric;        -- playback uses the chosen part (feed_posts view exposes both)
alter table public.groups add column if not exists is_private boolean not null default false;
-- table group_join_requests (group_id, user_id, created_at) with rules: a person can ask to join a private group,
-- admins can see and remove requests; function review_join_request(group, user, accept) lets an admin accept
-- (person becomes a member) or decline (request ends). Public groups: anyone may join directly.
-- Private groups: self-join is blocked by the database; only an approved request or an allowed invite adds a member.
-- Only admins can switch a group between public and private. Tested with temporary users.
