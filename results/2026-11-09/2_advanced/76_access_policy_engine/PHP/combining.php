<?php

function indeterminate(string $decision): bool
{
    return str_starts_with($decision, 'INDETERMINATE');
}

function combineElements(object $element, callable $evaluate, callable $target): object
{
    $children = [];
    foreach ($element->children as $child) {
        $children[] = (object) ['state' => 'skipped', 'element' => $child];
    }
    if ($element->algorithm === 'only-one-applicable') {
        $selected = null;
        foreach ($element->children as $index => $child) {
            $checked = $target($child);
            $children[$index] = (object) ['state' => 'checked', 'element' => $child, 'target' => $checked];
            if ($checked->status === 'INDETERMINATE') {
                return (object) ['decision' => 'INDETERMINATE{DP}', 'reason' => $checked->reason, 'children' => $children];
            }
            if ($checked->status === 'MATCH') {
                if ($selected !== null) {
                    return (object) ['decision' => 'INDETERMINATE{DP}', 'reason' => 'multiple applicable ' . $element->children[$selected]->id . ' ' . $child->id, 'children' => $children];
                }
                $selected = $index;
            }
        }
        if ($selected === null) {
            return (object) ['decision' => 'NOT_APPLICABLE', 'reason' => null, 'children' => $children];
        }
        $child = $element->children[$selected];
        $result = $evaluate($child);
        $children[$selected] = (object) ['state' => 'evaluated', 'element' => $child, 'result' => $result];
        return (object) ['decision' => $result->decision, 'reason' => $result->reason, 'children' => $children];
    }
    $evaluated = [];
    foreach ($element->children as $index => $child) {
        $result = $evaluate($child);
        $evaluated[] = $result;
        $children[$index] = (object) ['state' => 'evaluated', 'element' => $child, 'result' => $result];
        $algorithm = $element->algorithm;
        if ($algorithm === 'first-applicable' && $result->decision !== 'NOT_APPLICABLE') {
            return (object) ['decision' => $result->decision, 'reason' => $result->reason, 'children' => $children];
        }
        if (in_array($algorithm, ['deny-overrides', 'permit-unless-deny'], true) && $result->decision === 'DENY') {
            return (object) ['decision' => 'DENY', 'reason' => null, 'children' => $children];
        }
        if (in_array($algorithm, ['permit-overrides', 'deny-unless-permit'], true) && $result->decision === 'PERMIT') {
            return (object) ['decision' => 'PERMIT', 'reason' => null, 'children' => $children];
        }
    }
    $decisions = [];
    $reason = null;
    foreach ($evaluated as $result) {
        $decisions[$result->decision] = true;
        if ($reason === null && indeterminate($result->decision)) {
            $reason = $result->reason;
        }
    }
    $decision = 'NOT_APPLICABLE';
    if ($element->algorithm === 'deny-unless-permit') {
        $decision = 'DENY';
    } elseif ($element->algorithm === 'permit-unless-deny') {
        $decision = 'PERMIT';
    } elseif ($element->algorithm === 'deny-overrides') {
        if (isset($decisions['INDETERMINATE{DP}']) || (isset($decisions['INDETERMINATE{D}']) && (isset($decisions['INDETERMINATE{P}']) || isset($decisions['PERMIT'])))) {
            $decision = 'INDETERMINATE{DP}';
        } elseif (isset($decisions['INDETERMINATE{D}'])) {
            $decision = 'INDETERMINATE{D}';
        } elseif (isset($decisions['PERMIT'])) {
            $decision = 'PERMIT';
        } elseif (isset($decisions['INDETERMINATE{P}'])) {
            $decision = 'INDETERMINATE{P}';
        }
    } elseif ($element->algorithm === 'permit-overrides') {
        if (isset($decisions['INDETERMINATE{DP}']) || (isset($decisions['INDETERMINATE{P}']) && (isset($decisions['INDETERMINATE{D}']) || isset($decisions['DENY'])))) {
            $decision = 'INDETERMINATE{DP}';
        } elseif (isset($decisions['INDETERMINATE{P}'])) {
            $decision = 'INDETERMINATE{P}';
        } elseif (isset($decisions['DENY'])) {
            $decision = 'DENY';
        } elseif (isset($decisions['INDETERMINATE{D}'])) {
            $decision = 'INDETERMINATE{D}';
        }
    }
    return (object) ['decision' => $decision, 'reason' => indeterminate($decision) ? $reason : null, 'children' => $children];
}
