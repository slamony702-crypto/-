-- ═══════════════════════════════════════════════════════════
-- الشات المخصص + الأرشيف — إضافات آمنة لجدول conversations
-- ═══════════════════════════════════════════════════════════
alter table conversations add column if not exists is_archived boolean default false;
alter table conversations add column if not exists archived_at timestamptz;
alter table conversations add column if not exists archived_by bigint references users(id) on delete set null;
alter table conversations add column if not exists last_message_at timestamptz;
alter table conversations add column if not exists archive_reminder_sent_at timestamptz;
alter table conversations add column if not exists second_archive_reminder_sent_at timestamptz;
alter table conversations add column if not exists created_by bigint references users(id) on delete set null;

-- chat_type: نُحدّث لتشمل custom (بقيّة القيم موجودة كـ conversation_type)
-- direct | department | meeting | task | task_project | custom
-- لا نغيّر conversation_type — نضيف قيمة "custom" فقط

create index if not exists idx_conversations_archived on conversations(is_archived);
create index if not exists idx_conversations_type on conversations(conversation_type);
create index if not exists idx_conversations_last_msg on conversations(last_message_at desc);
