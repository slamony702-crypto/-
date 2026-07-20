-- ============================================================
-- موديول المحاسبة - نظام POS
-- SQLite Schema كامل
-- يغطي: القيد المزدوج، الفروع المتعددة، ضريبة القيمة المضافة،
--       الأصول الثابتة والإهلاك
-- ============================================================

PRAGMA foreign_keys = ON;

-- ============================================================
-- 1. الفروع (Branches)
-- ============================================================
CREATE TABLE branches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    code TEXT UNIQUE NOT NULL,        -- كود مختصر للفرع مثل "BR01"
    address TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,  -- 1 = نشط, 0 = مغلق
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================
-- 2. دليل الحسابات (Chart of Accounts)
-- ============================================================
CREATE TABLE accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,        -- كود الحساب مثل "1010"
    name TEXT NOT NULL,               -- اسم الحساب
    name_en TEXT,                     -- اسم بالإنجليزي (اختياري)
    account_type TEXT NOT NULL CHECK (account_type IN (
        'asset', 'liability', 'equity', 'revenue', 'expense'
    )),
    account_subtype TEXT,             -- مثال: 'cash','bank','inventory','receivable','payable','fixed_asset','accumulated_depreciation','tax_payable','tax_input'
    normal_balance TEXT NOT NULL CHECK (normal_balance IN ('debit','credit')),
    parent_account_id INTEGER REFERENCES accounts(id),  -- لو عايز حسابات فرعية (شجرة حسابات)
    is_active INTEGER NOT NULL DEFAULT 1,
    branch_id INTEGER REFERENCES branches(id),  -- NULL = حساب عام لكل الفروع
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_accounts_type ON accounts(account_type);
CREATE INDEX idx_accounts_branch ON accounts(branch_id);

-- ============================================================
-- 3. جهات الاتصال (موردين/عملاء موحدين)
-- ============================================================
CREATE TABLE contacts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('customer','supplier','both')),
    phone TEXT,
    email TEXT,
    address TEXT,
    tax_number TEXT,                  -- الرقم الضريبي (لو منشأة)
    -- كل contact مربوط بحساب مدين (عميل) و/أو حساب دائن (مورد) في دليل الحسابات
    receivable_account_id INTEGER REFERENCES accounts(id),  -- حساب عميل خاص به
    payable_account_id INTEGER REFERENCES accounts(id),     -- حساب مورد خاص به
    credit_limit REAL DEFAULT 0,      -- سقف الدين المسموح به (للعملاء)
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_contacts_type ON contacts(type);

-- ============================================================
-- 4. الأصول الثابتة (Fixed Assets)
-- ============================================================
CREATE TABLE fixed_assets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    branch_id INTEGER NOT NULL REFERENCES branches(id),
    name TEXT NOT NULL,
    asset_account_id INTEGER NOT NULL REFERENCES accounts(id),              -- حساب الأصل نفسه
    accumulated_depreciation_account_id INTEGER NOT NULL REFERENCES accounts(id), -- حساب مجمع الإهلاك
    depreciation_expense_account_id INTEGER NOT NULL REFERENCES accounts(id),     -- حساب مصروف الإهلاك
    purchase_date TEXT NOT NULL,
    purchase_cost REAL NOT NULL CHECK (purchase_cost >= 0),
    salvage_value REAL NOT NULL DEFAULT 0,   -- القيمة التخريدية بعد نهاية العمر الافتراضي
    useful_life_months INTEGER NOT NULL CHECK (useful_life_months > 0),
    depreciation_method TEXT NOT NULL DEFAULT 'straight_line'
        CHECK (depreciation_method IN ('straight_line')),  -- ممكن تضيف طرق تانية لاحقاً
    is_disposed INTEGER NOT NULL DEFAULT 0,  -- 1 لو الأصل اتباع/استبعد
    disposed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- سجل الإهلاك الشهري (لتتبع تاريخ كل قيد إهلاك)
CREATE TABLE depreciation_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    fixed_asset_id INTEGER NOT NULL REFERENCES fixed_assets(id),
    period TEXT NOT NULL,             -- مثال: '2026-07'
    amount REAL NOT NULL CHECK (amount >= 0),
    journal_entry_id INTEGER REFERENCES journal_entries(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (fixed_asset_id, period)   -- منع تسجيل إهلاك مرتين لنفس الشهر
);

-- ============================================================
-- 5. رأس القيد المحاسبي (Journal Entries)
-- ============================================================
CREATE TABLE journal_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    branch_id INTEGER NOT NULL REFERENCES branches(id),
    entry_date TEXT NOT NULL DEFAULT (date('now')),
    reference_type TEXT NOT NULL CHECK (reference_type IN (
        'sale','purchase','payment_received','payment_made',
        'sales_return','purchase_return','inventory_adjustment',
        'expense','depreciation','capital','manual','transfer'
    )),
    reference_id INTEGER,             -- يشاور على الفاتورة/العملية الأصلية (invoice id مثلاً)
    description TEXT NOT NULL,
    created_by TEXT,                  -- اسم المستخدم اللي سجل القيد
    is_posted INTEGER NOT NULL DEFAULT 1,  -- 1 = مرحّل ونهائي, 0 = مسودة
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_je_branch_date ON journal_entries(branch_id, entry_date);
CREATE INDEX idx_je_reference ON journal_entries(reference_type, reference_id);

-- ============================================================
-- 6. تفاصيل القيد (سطور المدين والدائن)
-- ============================================================
CREATE TABLE journal_entry_lines (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    journal_entry_id INTEGER NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
    account_id INTEGER NOT NULL REFERENCES accounts(id),
    contact_id INTEGER REFERENCES contacts(id),  -- لو السطر خاص بعميل/مورد معين
    debit REAL NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit REAL NOT NULL DEFAULT 0 CHECK (credit >= 0),
    notes TEXT,
    -- constraint: كل سطر إما مدين أو دائن، مش الاتنين مع بعض وبقيمة صفر
    CHECK (
        (debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)
    )
);

CREATE INDEX idx_jel_entry ON journal_entry_lines(journal_entry_id);
CREATE INDEX idx_jel_account ON journal_entry_lines(account_id);
CREATE INDEX idx_jel_contact ON journal_entry_lines(contact_id);

-- ============================================================
-- 7. Trigger: يمنع حفظ أي قيد غير متوازن (مدين ≠ دائن)
-- ============================================================
-- SQLite ماعندوش statement-level triggers بعد commit مباشر على نفس الجدول بسهولة،
-- فالتحقق الأدق بيتنفذ في الكود (Node.js) قبل الإدراج داخل transaction واحدة.
-- لكن نضيف trigger احترازي يتأكد إن مفيش سطر فاسد يتسجل منفرد:

CREATE TRIGGER trg_check_line_validity
BEFORE INSERT ON journal_entry_lines
FOR EACH ROW
BEGIN
    SELECT CASE
        WHEN NEW.debit > 0 AND NEW.credit > 0 THEN
            RAISE(ABORT, 'لا يمكن أن يكون السطر مدين ودائن في نفس الوقت')
        WHEN NEW.debit = 0 AND NEW.credit = 0 THEN
            RAISE(ABORT, 'السطر لازم يكون له قيمة مدين أو دائن')
    END;
END;

-- ============================================================
-- 8. ضريبة القيمة المضافة (VAT) - إعدادات
-- ============================================================
CREATE TABLE tax_rates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,               -- مثال: "ضريبة قيمة مضافة 15%"
    rate REAL NOT NULL CHECK (rate >= 0 AND rate <= 100),  -- نسبة مئوية
    tax_type TEXT NOT NULL CHECK (tax_type IN ('output','input')),  -- output = على المبيعات, input = على المشتريات
    account_id INTEGER NOT NULL REFERENCES accounts(id),  -- حساب الضريبة المرتبط
    is_active INTEGER NOT NULL DEFAULT 1
);

-- ============================================================
-- 9. الفواتير (بيع/شراء) - الطبقة اللي بتولد القيود
-- ============================================================
CREATE TABLE invoices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    branch_id INTEGER NOT NULL REFERENCES branches(id),
    invoice_type TEXT NOT NULL CHECK (invoice_type IN (
        'sale','purchase','sales_return','purchase_return'
    )),
    invoice_number TEXT NOT NULL,
    contact_id INTEGER REFERENCES contacts(id),
    invoice_date TEXT NOT NULL DEFAULT (date('now')),
    payment_method TEXT NOT NULL CHECK (payment_method IN ('cash','credit','bank')),
    subtotal REAL NOT NULL DEFAULT 0,      -- قبل الضريبة والخصم
    discount_amount REAL NOT NULL DEFAULT 0,
    tax_amount REAL NOT NULL DEFAULT 0,
    total_amount REAL NOT NULL DEFAULT 0,  -- subtotal - discount + tax
    journal_entry_id INTEGER REFERENCES journal_entries(id),  -- القيد الناتج عن الفاتورة
    status TEXT NOT NULL DEFAULT 'confirmed' CHECK (status IN ('draft','confirmed','cancelled')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (branch_id, invoice_type, invoice_number)
);

CREATE INDEX idx_invoices_contact ON invoices(contact_id);
CREATE INDEX idx_invoices_date ON invoices(invoice_date);

-- ============================================================
-- 10. أرصدة الحسابات (View محسوب) بدل تخزين رصيد مباشر
-- ============================================================
-- الرصيد بيتحسب دايماً من مجموع القيود، مش عمود مخزن، عشان نضمن الدقة 100%
CREATE VIEW account_balances AS
SELECT
    a.id AS account_id,
    a.code,
    a.name,
    a.account_type,
    a.normal_balance,
    a.branch_id,
    COALESCE(SUM(jel.debit), 0) AS total_debit,
    COALESCE(SUM(jel.credit), 0) AS total_credit,
    CASE
        WHEN a.normal_balance = 'debit'
            THEN COALESCE(SUM(jel.debit), 0) - COALESCE(SUM(jel.credit), 0)
        ELSE COALESCE(SUM(jel.credit), 0) - COALESCE(SUM(jel.debit), 0)
    END AS balance
FROM accounts a
LEFT JOIN journal_entry_lines jel ON jel.account_id = a.id
LEFT JOIN journal_entries je ON je.id = jel.journal_entry_id AND je.is_posted = 1
GROUP BY a.id;

-- رصيد كل عميل/مورد
CREATE VIEW contact_balances AS
SELECT
    c.id AS contact_id,
    c.name,
    c.type,
    COALESCE(SUM(CASE WHEN jel.account_id = c.receivable_account_id THEN jel.debit - jel.credit ELSE 0 END), 0) AS receivable_balance,
    COALESCE(SUM(CASE WHEN jel.account_id = c.payable_account_id THEN jel.credit - jel.debit ELSE 0 END), 0) AS payable_balance
FROM contacts c
LEFT JOIN journal_entry_lines jel ON jel.contact_id = c.id
LEFT JOIN journal_entries je ON je.id = jel.journal_entry_id AND je.is_posted = 1
GROUP BY c.id;
