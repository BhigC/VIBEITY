-- Applied to project obzmukyyfxxtqufabjjz (record of what was run). Safe to re-run.
alter table public.groups add column if not exists edit_policy text not null default 'admins';
alter table public.groups add column if not exists send_policy text not null default 'everyone';
-- helper functions: is_group_admin(), can_edit_group(), can_send_group_messages()
-- policies: groups_update (admins always, members only if edit_policy = 'everyone'),
--           group_messages_insert (follows send_policy), group_members update/delete for admins
-- triggers: protect_group (only admins change permissions), protect_member (only admins change roles; creator stays admin)
-- Tested with temporary users: creator = admin, members cannot self-promote or change permissions,
-- "admins only" blocks member messages, creator cannot be demoted.
