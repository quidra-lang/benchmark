<?php
const RULES_HEADER = 'rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement';
function fraction_text(Fraction $value): string {
    $numerator = abs($value->numerator); $denominator = $value->denominator; $scaled = intdiv(10000 * $numerator,$denominator); $decimal = intdiv($scaled,10000) . '.' . str_pad((string)($scaled % 10000),4,'0',STR_PAD_LEFT);
    return ($value->numerator < 0 ? '-' : '') . "$numerator/$denominator=" . ($value->numerator < 0 && $scaled > 0 ? '-' : '') . $decimal;
}
function percent_text(int $part, int $whole): string { $scaled = intdiv(10000 * $part,$whole); return intdiv($scaled,100) . '.' . str_pad((string)($scaled % 100),2,'0',STR_PAD_LEFT) . '%'; }
function money_text(int $cents): string { return intdiv($cents,100) . '.' . str_pad((string)($cents % 100),2,'0',STR_PAD_LEFT); }
function rule_arrow(Rule $rule): string { return set_key($rule->antecedent) . ' -> ' . set_key($rule->consequent); }
function rules_csv(array $rules): array {
    $lines = [RULES_HEADER];
    foreach ($rules as $rule) $lines[] = implode(',',[$rule->rank,set_key($rule->antecedent),set_key($rule->consequent),$rule->count,fraction_text($rule->support),fraction_text($rule->confidence),fraction_text($rule->lift),fraction_text($rule->leverage),$rule->conviction === null ? 'INF' : fraction_text($rule->conviction),fraction_text($rule->improvement)]);
    return $lines;
}
function write_report(string $name, array $lines): void { if (!is_dir('output')) mkdir('output',0777,true); file_put_contents("output/$name",$lines ? implode("\n",$lines) . "\n" : ''); }
