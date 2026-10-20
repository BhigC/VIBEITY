-- Applied to project obzmukyyfxxtqufabjjz (record of what was run). Safe to re-run.
-- comments can carry an image
alter table public.comments add column if not exists media_url text;
alter table public.comments alter column body drop not null;
alter table public.comments drop constraint if exists comments_body_check;
alter table public.comments add constraint comments_body_check check (body is null or char_length(body) between 1 and 500);
alter table public.comments drop constraint if exists comment_has_content;
alter table public.comments add constraint comment_has_content check (body is not null or media_url is not null);
-- chat messages: photos, videos, files, voice notes, view once
alter table public.messages add column if not exists kind text not null default 'text';
alter table public.messages add column if not exists media_url text;
alter table public.messages add column if not exists file_name text;
alter table public.messages add column if not exists file_size bigint;
alter table public.messages add column if not exists duration_s integer;
alter table public.messages add column if not exists view_once boolean not null default false;
create table if not exists public.message_opens (message_id bigint not null references public.messages(id) on delete cascade, user_id uuid not null references public.profiles(id) on delete cascade, opened_at timestamptz not null default now(), primary key (message_id, user_id));
-- per-person chat settings, blocks
alter table public.conversation_members add column if not exists muted boolean not null default false;
alter table public.conversation_members add column if not exists cleared_at timestamptz;
create table if not exists public.blocks (blocker uuid not null references public.profiles(id) on delete cascade, blocked uuid not null references public.profiles(id) on delete cascade, created_at timestamptz not null default now(), primary key (blocker, blocked), check (blocker <> blocked));
-- groups: photo, who can add, roles, personal settings, media in group chat
alter table public.groups add column if not exists photo_url text;
alter table public.groups add column if not exists add_policy text not null default 'everyone';
alter table public.group_members add column if not exists role text not null default 'member';
alter table public.group_members add column if not exists muted boolean not null default false;
alter table public.group_members add column if not exists pinned boolean not null default false;
alter table public.group_members add column if not exists cleared_at timestamptz;
alter table public.group_members add column if not exists ringtone text not null default 'classic';
alter table public.group_members add column if not exists theme text not null default 'default';
alter table public.group_members add column if not exists last_read_at timestamptz not null default now();
alter table public.group_messages add column if not exists kind text not null default 'text';
alter table public.group_messages add column if not exists media_url text;
alter table public.group_messages add column if not exists file_name text;
alter table public.group_messages add column if not exists file_size bigint;
alter table public.group_messages add column if not exists duration_s integer;
alter table public.group_messages add column if not exists view_once boolean not null default false;
-- (policies, can_add_group_members() and the updated start_chat() were applied in the same migration)
