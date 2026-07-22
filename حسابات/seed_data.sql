-- ============================================================
-- بيانات ابتدائية (Seed Data)
-- ============================================================

-- ------------------------------------------------------------
-- 1. الفروع (مثال: فرعين، عدّل حسب الواقع)
-- ------------------------------------------------------------
INSERT INTO branches (name, code, address) VALUES
('الفرع الرئيسي', 'BR01', 'العنوان هنا'),
('الفرع الثاني', 'BR02', 'العنوان هنا');

-- ------------------------------------------------------------
-- 2. دليل الحسابات (Chart of Accounts)
-- الأكواد بنظام معياري:
-- 1xxx = أصول | 2xxx = خصوم | 3xxx = حقوق ملكية
-- 4xxx = إيرادات | 5xxx = مصروفات
-- ------------------------------------------------------------

-- الأصول (Assets)
INSERT INTO accounts (code, name, name_en, account_type, account_subtype, normal_balance) VALUES
('1010', 'الصندوق', 'Cash', 'asset', 'cash', 'debit'),
('1020', 'البنك', 'Bank', 'asset', 'bank', 'debit'),
('1030', 'عملاء - حسابات مدينة', 'Accounts Receivable', 'asset', 'receivable', 'debit'),
('1040', 'المخزون', 'Inventory', 'asset', 'inventory', 'debit'),
('1050', 'ضريبة مدخلات (قابلة للخصم)', 'VAT Input', 'asset', 'tax_input', 'debit'),
('1060', 'أصول ثابتة - معدات وأجهزة', 'Fixed Assets - Equipment', 'asset', 'fixed_asset', 'debit'),
('1061', 'مجمع إهلاك المعدات', 'Accumulated Depreciation - Equipment', 'asset', 'accumulated_depreciation', 'credit');

-- الخصوم (Liabilities)
INSERT INTO accounts (code, name, name_en, account_type, account_subtype, normal_balance) VALUES
('2010', 'موردين - حسابات دائنة', 'Accounts Payable', 'liability', 'payable', 'credit'),
('2020', 'ضريبة مخرجات مستحقة', 'VAT Payable', 'liability', 'tax_payable', 'credit'),
('2030', 'مصروفات مستحقة', 'Accrued Expenses', 'liability', 'accrued', 'credit');

-- حقوق الملكية (Equity)
INSERT INTO accounts (code, name, name_en, account_type, account_subtype, normal_balance) VALUES
('3010', 'رأس المال', 'Owner Capital', 'equity', 'capital', 'credit'),
('3020', 'مسحوبات شخصية', 'Owner Drawings', 'equity', 'drawings', 'debit'),
('3030', 'أرباح محتجزة', 'Retained Earnings', 'equity', 'retained_earnings', 'credit');

-- الإيرادات (Revenue)
INSERT INTO accounts (code, name, name_en, account_type, account_subtype, normal_balance) VALUES
('4010', 'المبيعات', 'Sales Revenue', 'revenue', 'sales', 'credit'),
('4020', 'مرتجعات المبيعات', 'Sales Returns', 'revenue', 'sales_return', 'debit'),
('4030', 'خصم مسموح به', 'Sales Discount', 'revenue', 'sales_discount', 'debit'),
('4040', 'خصم مكتسب من موردين', 'Purchase Discount Income', 'revenue', 'purchase_discount', 'credit'),
('4050', 'أرباح تسوية مخزون', 'Inventory Adjustment Gain', 'revenue', 'inventory_gain', 'credit');

-- المصروفات (Expenses)
INSERT INTO accounts (code, name, name_en, account_type, account_subtype, normal_balance) VALUES
('5010', 'تكلفة البضاعة المباعة', 'Cost of Goods Sold', 'expense', 'cogs', 'debit'),
('5020', 'مصروف إيجار', 'Rent Expense', 'expense', 'rent', 'debit'),
('5030', 'مصروف كهرباء ومرافق', 'Utilities Expense', 'expense', 'utilities', 'debit'),
('5040', 'مصروف رواتب', 'Salaries Expense', 'expense', 'salaries', 'debit'),
('5050', 'مصروف إهلاك', 'Depreciation Expense', 'expense', 'depreciation', 'debit'),
('5060', 'خسارة تسوية مخزون', 'Inventory Shrinkage', 'expense', 'inventory_loss', 'debit'),
('5070', 'مصروف ديون معدومة', 'Bad Debt Expense', 'expense', 'bad_debt', 'debit'),
('5080', 'خسارة عجز صندوق', 'Cash Shortage Loss', 'expense', 'cash_shortage', 'debit');

-- ------------------------------------------------------------
-- 3. ضريبة القيمة المضافة (مثال بنسبة 15%، عدّل حسب بلدك)
-- ------------------------------------------------------------
INSERT INTO tax_rates (name, rate, tax_type, account_id) VALUES
('ضريبة قيمة مضافة على المبيعات 15%', 15.0, 'output',
    (SELECT id FROM accounts WHERE code = '2020')),
('ضريبة قيمة مضافة على المشتريات 15%', 15.0, 'input',
    (SELECT id FROM accounts WHERE code = '1050'));
