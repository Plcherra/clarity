/// Normalized key for monthly budget maps and SharedPreferences storage.
///
/// Must match how spending aggregates label categories after display renames
/// (same strings as `CategorySpend.name` in monthly aggregates): callers pass the **display**
/// label for a category row, then use this for lookup and persistence keys.
String budgetDisplayKey(String displayLabel) => displayLabel.trim().toLowerCase();

