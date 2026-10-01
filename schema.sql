-- Yo7 Solutions — database schema reference
--
-- NOTE ON SCOPE: this file does not yet contain a full schema dump (tables,
-- indexes, RLS policies, triggers) — only the RPC functions below have been
-- verified against a live deployment. If you're setting up a brand-new
-- Supabase project, you'll still need to create the `settings`, `customers`,
-- `invoices`, `invoice_items`, `products`, `stock_movements`, `payments`,
-- `reminders`, and `activity_log` tables yourself, with Row Level Security
-- enabled on each and scoped to shared `business_id` membership (see the
-- README's Security model section). Pulling a full `pg_dump` of an existing
-- project's schema (table definitions + policies) and merging it into this
-- file would close that gap — ask Claude to do it next time it has access to
-- the live project.
--
-- Safe to re-run: every statement below uses CREATE OR REPLACE, so re-running
-- this file against a project that already has these functions just updates
-- them in place.

-- Powers the public, login-free invoice tracking link ("?track=<token>").
-- Returns one invoice's data, plus the business's live branding and payment
-- details, by its unguessable tracking token — never a general query surface.
--
-- IMPORTANT: the `company` object below must list every settings column the
-- public tracking page (renderPublicTrackingPage in index.html) reads. If a
-- new field is added to Settings that should also show on the public page
-- (for example a future branding field), it needs to be added here too —
-- this function does not `select *`, so a column that exists on `settings`
-- but is missing from this json_build_object silently never reaches the
-- public page, however correct the app code is.
CREATE OR REPLACE FUNCTION public.get_invoice_public(p_token uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result json;
begin
  select json_build_object(
    'number', i.number,
    'issue_date', i.issue_date,
    'due_date', i.due_date,
    'tax_rate', i.tax_rate,
    'delivery_fee', i.delivery_fee,
    'notes', i.notes,
    'status', i.status,
    'customer_name', c.name,
    'customer_email', c.email,
    'items', (
      select json_agg(json_build_object('name', it.name, 'qty', it.qty, 'price', it.price, 'unit', it.unit))
      from invoice_items it where it.invoice_id = i.id
    ),
    'paid', coalesce((select sum(p.amount) from payments p where p.invoice_id = i.id), 0),
    'payments', (
      select json_agg(json_build_object('date', p.date, 'amount', p.amount, 'method', p.method) order by p.date)
      from payments p where p.invoice_id = i.id
    ),
    'company', (
      select json_build_object(
        'name', s.company_name, 'email', s.email, 'phone', s.phone,
        'address', s.address, 'website', s.website,
        'logo_data_url', s.logo_data_url, 'invoice_footer_message', s.invoice_footer_message,
        'bank_name', s.bank_name, 'account_holder', s.account_holder,
        'account_number', s.account_number, 'sort_code', s.sort_code,
        'payment_reference', s.payment_reference
      ) from settings s where s.business_id = i.business_id
    )
  ) into result
  from invoices i
  left join customers c on c.id = i.customer_id
  where i.tracking_token = p_token;

  return result;
end;
$function$;
