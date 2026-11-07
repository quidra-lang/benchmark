<?php

require_once __DIR__ . '/rbac.php';
require_once __DIR__ . '/expressions.php';
require_once __DIR__ . '/policy_parser.php';
require_once __DIR__ . '/combining.php';
require_once __DIR__ . '/analysis.php';

function definite(string $decision): bool
{
    return $decision === 'PERMIT' || $decision === 'DENY';
}

function failure(string $reason): object
{
    return (object) ['error' => $reason];
}

function isFailure($value): bool
{
    return is_object($value) && property_exists($value, 'error');
}

function effectError(string $effect): string
{
    return 'INDETERMINATE{' . ($effect === 'DENY' ? 'D' : 'P') . '}';
}

function readLines(string $name): array
{
    return file('input/' . $name, FILE_IGNORE_NEW_LINES);
}

function parseValue(string $text)
{
    if ($text === 'true' || $text === 'false') {
        return $text === 'true';
    }
    if (preg_match('/^-?[0-9]+$/', $text)) {
        return (int) $text;
    }
    if (str_starts_with($text, '[')) {
        return $text === '[]' ? [] : explode(',', substr($text, 1, -1));
    }
    return $text;
}

function valueNotation($value): string
{
    if (is_array($value)) {
        return '[' . implode(',', array_map(fn($item) => '"' . $item . '"', $value)) . ']';
    }
    if (is_string($value)) {
        return '"' . $value . '"';
    }
    if (is_bool($value)) {
        return $value ? 'true' : 'false';
    }
    return (string) $value;
}

function attributes(array $tokens): array
{
    $result = [];
    foreach ($tokens as $token) {
        $separator = strpos($token, '=');
        $result[substr($token, 0, $separator)] = parseValue(substr($token, $separator + 1));
    }
    return $result;
}

function readAttributes(): object
{
    $subjects = $resources = $domains = [];
    $reference = [];
    foreach (readLines('attributes.txt') as $line) {
        $fields = explode(' ', $line);
        if ($fields[0] === 'SUBJECT') {
            $subjects[$fields[1]] = attributes(array_slice($fields, 2));
        } elseif ($fields[0] === 'RESOURCE') {
            $resources[$fields[1]] = (object) ['id' => $fields[1], 'type' => $fields[2], 'attributes' => attributes(array_slice($fields, 3))];
        } elseif ($fields[0] === 'DOMAIN') {
            $domains[] = (object) ['reference' => $fields[1], 'values' => array_map('parseValue', array_slice($fields, 2))];
        } else {
            $reference = attributes(array_slice($fields, 1));
        }
    }
    return (object) compact('subjects', 'resources', 'domains', 'reference');
}

function readRequests(): array
{
    $requests = [];
    foreach (readLines('requests.txt') as $line) {
        $fields = explode(' ', $line);
        $explained = $fields[count($fields) - 1] === 'EXPLAIN';
        if ($explained) {
            array_pop($fields);
        }
        $requests[] = (object) ['id' => $fields[0], 'user' => $fields[1], 'roleSpec' => $fields[2], 'action' => $fields[3],
            'resourceId' => $fields[4], 'environment' => attributes(array_slice($fields, 5)), 'explained' => $explained];
    }
    return $requests;
}

function typedBoolean($value, string $operation)
{
    return is_bool($value) || isFailure($value) ? $value : failure('type ' . $operation);
}

function logical(string $operation, array $values)
{
    $operands = array_map(fn($value) => typedBoolean($value, $operation), $values);
    $conjunction = $operation === 'and' || $operation === 'all_of';
    foreach ($operands as $operand) {
        if ($operand === !$conjunction) {
            return !$conjunction;
        }
    }
    foreach ($operands as $operand) {
        if (isFailure($operand)) {
            return $operand;
        }
    }
    return $conjunction;
}

function applyOperation(string $operation, array $values)
{
    foreach ($values as $value) {
        if (isFailure($value)) {
            return $value;
        }
    }
    $first = $values[0];
    $second = $values[1] ?? null;
    $integers = count(array_filter($values, 'is_int')) === count($values);
    $strings = count(array_filter($values, 'is_string')) === count($values);
    switch ($operation) {
        case '+': if ($integers) return $first + $second; break;
        case '-': if ($integers) return count($values) === 1 ? -$first : $first - $second; break;
        case '*': if ($integers) return $first * $second; break;
        case '==':
        case '!=':
            if (gettype($first) === gettype($second) && (is_int($first) || is_bool($first) || is_string($first))) {
                return $operation === '==' ? $first === $second : $first !== $second;
            }
            break;
        case '<': if ($integers) return $first < $second; break;
        case '<=': if ($integers) return $first <= $second; break;
        case '>': if ($integers) return $first > $second; break;
        case '>=': if ($integers) return $first >= $second; break;
        case 'in': if (is_string($first) && is_array($second)) return in_array($first, $second, true); break;
        case 'not': if (is_bool($first)) return !$first; break;
        case 'starts_with':
        case '^=': if ($strings) return str_starts_with($first, $second); break;
        case 'size': if (is_array($first)) return count($first); break;
    }
    return failure('type ' . $operation);
}

function evaluateExpression(object $expression, array $attributeSet, $currentItem = null)
{
    if ($expression->kind === 'literal') {
        return $expression->value;
    }
    if ($expression->kind === 'it') {
        return $currentItem;
    }
    if ($expression->kind === 'attribute') {
        return array_key_exists($expression->name, $attributeSet) ? $attributeSet[$expression->name] : failure('missing ' . $expression->name);
    }
    $operation = $expression->operation;
    if ($operation === 'present') {
        return array_key_exists($expression->arguments[0]->name, $attributeSet);
    }
    if ($operation === 'any_of' || $operation === 'all_of') {
        $bag = evaluateExpression($expression->arguments[0], $attributeSet, $currentItem);
        if (isFailure($bag)) {
            return $bag;
        }
        if (!is_array($bag)) {
            return failure('type ' . $operation);
        }
        $values = [];
        foreach ($bag as $item) {
            $values[] = evaluateExpression($expression->arguments[1], $attributeSet, $item);
        }
        return logical($operation, $values);
    }
    $values = [];
    foreach ($expression->arguments as $argument) {
        $values[] = evaluateExpression($argument, $attributeSet, $currentItem);
    }
    return $operation === 'and' || $operation === 'or' ? logical($operation, $values) : applyOperation($operation, $values);
}

function matchClause(object $clause, array $attributeSet): object
{
    if (!array_key_exists($clause->reference, $attributeSet)) {
        return $clause->mandatory ? (object) ['status' => 'INDETERMINATE', 'reason' => 'missing ' . $clause->reference] : (object) ['status' => 'NO_MATCH'];
    }
    $value = $attributeSet[$clause->reference];
    $items = is_array($value) ? $value : [$value];
    $firstFailure = null;
    $matched = false;
    foreach ($items as $item) {
        $result = applyOperation($clause->operation, [$item, $clause->literal]);
        if ($result === true) {
            $matched = true;
        } elseif (isFailure($result) && $firstFailure === null) {
            $firstFailure = $result;
        }
    }
    if ($matched) {
        return (object) ['status' => 'MATCH'];
    }
    return $firstFailure === null ? (object) ['status' => 'NO_MATCH'] : (object) ['status' => 'INDETERMINATE', 'reason' => $firstFailure->error];
}

function targetAnd(array $results): object
{
    foreach ($results as $result) {
        if ($result->status === 'NO_MATCH') {
            return (object) ['status' => 'NO_MATCH'];
        }
    }
    foreach ($results as $result) {
        if ($result->status === 'INDETERMINATE') {
            return $result;
        }
    }
    return (object) ['status' => 'MATCH'];
}

function targetOr(array $results): object
{
    foreach ($results as $result) {
        if ($result->status === 'MATCH') {
            return (object) ['status' => 'MATCH'];
        }
    }
    foreach ($results as $result) {
        if ($result->status === 'INDETERMINATE') {
            return $result;
        }
    }
    return (object) ['status' => 'NO_MATCH'];
}

function evaluateTarget(object $element, array $attributeSet): object
{
    $lines = [];
    foreach ($element->targets as $line) {
        $alternatives = [];
        foreach ($line as $alternative) {
            $clauses = [];
            foreach ($alternative as $clause) {
                $clauses[] = matchClause($clause, $attributeSet);
            }
            $alternatives[] = targetAnd($clauses);
        }
        $lines[] = targetOr($alternatives);
    }
    return targetAnd($lines);
}

function emptyResult(object $element, object $target): object
{
    return (object) ['element' => $element, 'target' => $target, 'decision' => 'NOT_APPLICABLE', 'reason' => null,
        'decisive' => null, 'obligations' => [], 'advice' => [], 'children' => []];
}

function ruleValue(object $element, array $attributeSet, object $target): object
{
    $result = emptyResult($element, $target);
    if ($target->status === 'NO_MATCH') {
        return $result;
    }
    if ($target->status === 'INDETERMINATE') {
        $result->decision = effectError($element->effect);
        $result->reason = $target->reason;
        return $result;
    }
    $result->condition = $element->condition === null ? true : typedBoolean(evaluateExpression($element->condition, $attributeSet), 'condition');
    if ($result->condition === true) {
        $result->decision = $element->effect;
        $result->decisive = $element->id;
    } elseif (isFailure($result->condition)) {
        $result->decision = effectError($element->effect);
        $result->reason = $result->condition->error;
    }
    return $result;
}

function attachment(object $item, array $attributeSet): object
{
    $values = [];
    foreach ($item->arguments as $argument) {
        $values[] = evaluateExpression($argument->expression, $attributeSet);
    }
    foreach ($values as $value) {
        if (isFailure($value)) {
            return $value;
        }
    }
    $text = $item->id;
    foreach ($values as $index => $value) {
        $text .= ' ' . $item->arguments[$index]->name . '=' . valueNotation($value);
    }
    return (object) ['id' => $item->id, 'text' => $text];
}

function attachObligations(object $result, array $attributeSet, array $supporters): void
{
    $decision = $result->decision;
    foreach ($supporters as $supporter) {
        $result->obligations = array_merge($result->obligations, $supporter->obligations);
        $result->advice = array_merge($result->advice, $supporter->advice);
    }
    foreach ($result->element->obligations as $obligation) {
        if ($obligation->effect !== $decision) {
            continue;
        }
        $item = attachment($obligation, $attributeSet);
        if (isFailure($item)) {
            $result->decision = effectError($decision);
            $result->reason = 'obligation ' . $obligation->id . ': ' . $item->error;
            $result->decisive = null;
            $result->obligations = [];
            $result->advice = [];
            return;
        }
        $result->obligations[] = $item;
    }
    foreach ($result->element->advice as $advice) {
        if ($advice->effect !== $decision) {
            continue;
        }
        $item = attachment($advice, $attributeSet);
        if (!isFailure($item)) {
            $result->advice[] = $item;
        }
    }
}

function evaluateElement(object $element, array $attributeSet, ?array &$coverage): object
{
    $target = evaluateTarget($element, $attributeSet);
    if ($element->kind === 'rule') {
        $result = ruleValue($element, $attributeSet, $target);
        if (definite($result->decision)) {
            attachObligations($result, $attributeSet, []);
        }
        if ($coverage !== null) {
            $coverage[$element->id] = $result->decision === 'PERMIT' ? 'P' : ($result->decision === 'DENY' ? 'D' : ($result->decision === 'NOT_APPLICABLE' ? '-' : 'I'));
        }
        return $result;
    }
    $result = emptyResult($element, $target);
    if ($target->status === 'NO_MATCH') {
        return $result;
    }
    $combined = combineElements($element,
        function ($child) use ($attributeSet, &$coverage) { return evaluateElement($child, $attributeSet, $coverage); },
        fn($child) => evaluateTarget($child, $attributeSet));
    $result->children = $combined->children;
    $result->decision = $combined->decision;
    $result->reason = $combined->reason;
    if ($target->status === 'INDETERMINATE') {
        if (definite($result->decision)) {
            $result->decision = effectError($result->decision);
        }
        if (indeterminate($result->decision)) {
            $result->reason = $target->reason;
        }
    }
    if (definite($result->decision)) {
        $supporters = [];
        foreach ($result->children as $child) {
            if ($child->state === 'evaluated' && $child->result->decision === $result->decision) {
                $supporters[] = $child->result;
            }
        }
        $result->decisive = count($supporters) === 0 ? $element->id : $supporters[0]->decisive;
        attachObligations($result, $attributeSet, $supporters);
    }
    return $result;
}

function activate(object $request, object $context, int $day, object $resource): object
{
    $rbac = $context->rbac;
    $authorized = $rbac->authorized($request->user, $day);
    if ($request->roleSpec === '-') {
        $candidates = [];
    } elseif ($request->roleSpec === '*') {
        $candidates = array_keys($authorized);
        sort($candidates, SORT_STRING);
    } else {
        $candidates = explode(',', $request->roleSpec);
    }
    $seen = [];
    $active = [];
    $activations = [];
    foreach ($candidates as $role) {
        $duplicate = isset($seen[$role]);
        $seen[$role] = true;
        $reason = null;
        if (!isset($rbac->roles[$role])) {
            $reason = 'unknown';
        } elseif ($duplicate) {
            $reason = 'duplicate';
        } elseif (!isset($authorized[$role])) {
            $reason = 'unauthorized';
        } else {
            $expanded = $rbac->closure(array_merge($active, [$role]));
            foreach ($rbac->dsd as $constraint) {
                $overlap = count(array_filter($constraint->roles, fn($item) => isset($expanded[$item])));
                if ($overlap >= $constraint->cardinality) {
                    $reason = 'dsd ' . $constraint->name;
                    break;
                }
            }
        }
        if ($reason === null) {
            $active[] = $role;
        }
        $activations[] = (object) compact('role', 'reason');
    }
    $session = array_keys($rbac->closure($active));
    sort($session, SORT_STRING);
    $key = permissionKey($request->action, $resource->type);
    $granting = null;
    foreach ($session as $role) {
        if (isset($rbac->roles[$role]->permissions[$key])) {
            $granting = $role;
            break;
        }
    }
    return (object) compact('activations', 'session', 'granting');
}

function requestAttributes(object $request, object $context, object $resource, object $activation): array
{
    $result = [];
    foreach ($context->data->subjects[$request->user] as $name => $value) {
        $result['subject.' . $name] = $value;
    }
    $result['subject.id'] = $request->user;
    $result['subject.role'] = $activation->session;
    $result['subject.rbac'] = $activation->granting !== null;
    foreach ($resource->attributes as $name => $value) {
        $result['resource.' . $name] = $value;
    }
    $result['resource.id'] = $resource->id;
    $result['resource.type'] = $resource->type;
    $result['action.id'] = $request->action;
    foreach ($request->environment as $name => $value) {
        $result['environment.' . $name] = $value;
    }
    return $result;
}

function evaluateRequest(object $request, object $context, bool $recordCoverage = false): object
{
    $coverage = null;
    if ($recordCoverage) {
        $coverage = [];
        foreach ($context->policies->rules as $rule) {
            $coverage[$rule->id] = '.';
        }
    }
    $message = null;
    $day = $request->environment['day'] ?? null;
    if (!array_key_exists($request->user, $context->data->subjects)) {
        $message = 'unknown user ' . $request->user;
    } elseif (!isset($context->data->resources[$request->resourceId])) {
        $message = 'unknown resource ' . $request->resourceId;
    } elseif (!is_int($day) || $day < 1 || $day > 365) {
        $message = 'bad day';
    }
    if ($message !== null) {
        return (object) ['request' => $request, 'error' => $message, 'coverage' => $coverage];
    }
    $resource = $context->data->resources[$request->resourceId];
    $activation = activate($request, $context, $day, $resource);
    $attributeSet = requestAttributes($request, $context, $resource, $activation);
    $evaluation = evaluateElement($context->policies->root, $attributeSet, $coverage);
    return (object) ['request' => $request, 'error' => null, 'day' => $day, 'resource' => $resource,
        'activations' => $activation->activations, 'session' => $activation->session, 'granting' => $activation->granting,
        'evaluation' => $evaluation, 'coverage' => $coverage];
}

function decisionNotation(object $result): string
{
    return $result->decision . (indeterminate($result->decision) ? ' (' . $result->reason . ')' : '');
}

function requestDecision(object $record): string
{
    if ($record->error !== null) {
        return 'ERROR ' . $record->error;
    }
    $result = $record->evaluation;
    return decisionNotation($result) . (definite($result->decision) ? ' by ' . $result->decisive : '');
}

function treeLines(object $result, int $depth = 0): array
{
    $indent = str_repeat(' ', 2 + 2 * $depth);
    $element = $result->element;
    $line = $indent . $element->kind . ' ' . $element->id . ' ' . ($element->kind === 'rule' ? $element->effect : $element->algorithm)
        . ' target ' . $result->target->status;
    if ($element->kind === 'rule' && $result->target->status === 'MATCH') {
        $line .= ' condition ' . ($result->condition === true ? 'TRUE' : ($result->condition === false ? 'FALSE' : 'INDETERMINATE'));
    }
    $lines = [$line . ' -> ' . decisionNotation($result)];
    if ($element->kind === 'rule' || $result->target->status === 'NO_MATCH') {
        return $lines;
    }
    foreach ($result->children as $child) {
        if ($child->state === 'evaluated') {
            $lines = array_merge($lines, treeLines($child->result, $depth + 1));
        } elseif ($child->state === 'skipped') {
            $lines[] = $indent . '  ' . $child->element->kind . ' ' . $child->element->id . ' skipped';
        } else {
            $checked = $indent . '  ' . $child->element->kind . ' ' . $child->element->id . ' ' . $child->element->algorithm . ' target ' . $child->target->status;
            if ($child->target->status === 'INDETERMINATE') {
                $checked .= ' (' . $child->target->reason . ')';
            }
            $lines[] = $checked;
        }
    }
    return $lines;
}

function decisionsLines(array $records): array
{
    $lines = [];
    foreach ($records as $record) {
        $lines[] = $record->request->id . ' ' . requestDecision($record);
        if ($record->error !== null) {
            continue;
        }
        foreach ($record->activations as $activation) {
            if ($activation->reason !== null) {
                $lines[] = '  refused ' . $activation->role . ' ' . $activation->reason;
            }
        }
        foreach ($record->evaluation->obligations as $obligation) {
            $lines[] = '  obligation ' . $obligation->text;
        }
        foreach ($record->evaluation->advice as $advice) {
            $lines[] = '  advice ' . $advice->text;
        }
    }
    return $lines;
}

function traceLines(array $records): array
{
    $lines = [];
    foreach ($records as $record) {
        if (!$record->request->explained) {
            continue;
        }
        if (count($lines)) {
            $lines[] = '';
        }
        $lines[] = 'request ' . $record->request->id;
        if ($record->error !== null) {
            $lines[] = '  error ' . $record->error;
            continue;
        }
        $request = $record->request;
        $lines[] = '  user ' . $request->user . ' resource ' . $request->resourceId . ' type ' . $record->resource->type . ' action ' . $request->action . ' day ' . $record->day;
        foreach ($record->activations as $activation) {
            $lines[] = '  activate ' . $activation->role . ' ' . ($activation->reason === null ? 'ok' : 'refused ' . $activation->reason);
        }
        $lines[] = '  roles ' . (count($record->session) ? implode(',', $record->session) : '-');
        $lines[] = $record->granting === null ? '  rbac no' : '  rbac yes ' . $record->granting;
        $lines = array_merge($lines, treeLines($record->evaluation));
        $lines[] = '  decision ' . requestDecision($record);
    }
    return $lines;
}

function mergeDays(array &$mapping, string $key, array $days): void
{
    foreach ($days as $day => $unused) {
        $mapping[$key][$day] = true;
    }
}

function permissionLines(object $context): array
{
    $lines = [];
    $users = array_keys($context->rbac->byUser);
    sort($users, SORT_STRING);
    foreach ($users as $user) {
        if (count($lines)) {
            $lines[] = '';
        }
        $lines[] = 'user ' . $user;
        $assigned = [];
        foreach ($context->rbac->byUser[$user] as $assignment) {
            for ($day = $assignment->first; $day <= $assignment->last; $day++) {
                $assigned[$assignment->role][$day] = true;
            }
        }
        $assignedRoles = array_keys($assigned);
        sort($assignedRoles, SORT_STRING);
        foreach ($assignedRoles as $role) {
            $lines[] = '  assigned ' . $role . ' ' . dayNotation($assigned[$role]);
        }
        $authorized = [];
        foreach ($assigned as $role => $days) {
            foreach ($context->rbac->closure([$role]) as $inherited => $unused) {
                mergeDays($authorized, $inherited, $days);
            }
        }
        $authorizedRoles = array_keys($authorized);
        sort($authorizedRoles, SORT_STRING);
        foreach ($authorizedRoles as $role) {
            $lines[] = '  authorized ' . $role . ' ' . dayNotation($authorized[$role]);
        }
        $permissions = [];
        foreach ($context->rbac->permissions as $permission) {
            if (!isset($authorized[$permission->role])) {
                continue;
            }
            $key = permissionKey($permission->action, $permission->type);
            if (!isset($permissions[$key])) {
                $permissions[$key] = (object) ['action' => $permission->action, 'type' => $permission->type, 'days' => [], 'via' => []];
            }
            $permissions[$key]->via[$permission->role] = true;
            foreach ($authorized[$permission->role] as $day => $unused) {
                $permissions[$key]->days[$day] = true;
            }
        }
        $ordered = array_values($permissions);
        usort($ordered, fn($a, $b) => strcmp($a->action, $b->action) ?: strcmp($a->type, $b->type));
        foreach ($ordered as $permission) {
            $effective = '-';
            if (array_key_exists($user, $context->data->subjects)) {
                $available = $permitted = 0;
                foreach ($context->data->resources as $resource) {
                    if ($resource->type !== $permission->type) {
                        continue;
                    }
                    $available++;
                    $hypothetical = (object) ['user' => $user, 'roleSpec' => '*', 'action' => $permission->action,
                        'resourceId' => $resource->id, 'environment' => $context->data->reference];
                    if (evaluateRequest($hypothetical, $context)->evaluation->decision === 'PERMIT') {
                        $permitted++;
                    }
                }
                $effective = $permitted . '/' . $available;
            }
            $via = array_keys($permission->via);
            sort($via, SORT_STRING);
            $lines[] = '  permission ' . $permission->action . ' ' . $permission->type . ' ' . dayNotation($permission->days)
                . ' via ' . implode(',', $via) . ' effective ' . $effective;
        }
    }
    return $lines;
}

function analyzeDomains(object $context): object
{
    $elements = $context->policies->elements;
    $rules = $context->policies->rules;
    $statistics = [];
    foreach ($rules as $rule) {
        $statistics[$rule->id] = (object) ['rule' => $rule, 'count' => 0, 'first' => null, 'blocked' => 0, 'blockers' => []];
    }
    $pairs = [];
    foreach ($elements as $policy) {
        if ($policy->kind !== 'policy') {
            continue;
        }
        for ($first = 0; $first < count($policy->children); $first++) {
            for ($second = $first + 1; $second < count($policy->children); $second++) {
                $a = $policy->children[$first];
                $b = $policy->children[$second];
                if ($a->effect !== $b->effect) {
                    $pairs[] = (object) ['policy' => $policy, 'first' => $a, 'second' => $b, 'count' => 0];
                }
            }
        }
    }
    $count = 0;
    foreach (points($context->data->domains) as $point) {
        $count++;
        $targets = [];
        $ancestorsMatch = [];
        foreach ($elements as $element) {
            $targets[$element->id] = evaluateTarget($element, $point);
            $ancestorsMatch[$element->id] = $targets[$element->id]->status === 'MATCH'
                && ($element->parent === null || $ancestorsMatch[$element->parent->id]);
        }
        $values = [];
        foreach ($rules as $rule) {
            $values[$rule->id] = ruleValue($rule, $point, $targets[$rule->id])->decision;
        }
        $applies = [];
        foreach ($rules as $rule) {
            if (!$ancestorsMatch[$rule->parent->id] || !definite($values[$rule->id])) {
                continue;
            }
            $applies[$rule->id] = true;
            $statistic = $statistics[$rule->id];
            $statistic->count++;
            if ($statistic->first === null) {
                $statistic->first = $point;
            }
            if ($rule->parent->algorithm === 'first-applicable') {
                $earlier = blocker($rule, $values);
                if ($earlier !== null) {
                    $statistic->blocked++;
                    $statistic->blockers[$earlier->id] = true;
                }
            }
        }
        foreach ($pairs as $pair) {
            if (isset($applies[$pair->first->id]) && isset($applies[$pair->second->id])) {
                $pair->count++;
            }
        }
    }
    $pairs = array_values(array_filter($pairs, fn($pair) => $pair->count > 0));
    return (object) compact('count', 'statistics', 'pairs');
}

function exampleNotation(array $domains, ?array $point): string
{
    if ($point === null) {
        return '-';
    }
    $parts = [];
    foreach ($domains as $domain) {
        if (count($domain->values) >= 2) {
            $parts[] = $domain->reference . '=' . valueNotation($point[$domain->reference]);
        }
    }
    return implode(' ', $parts);
}

function domainLines(object $context, object $domains): array
{
    $rules = $context->policies->rules;
    $lines = ['applicability ' . $domains->count];
    foreach ($rules as $rule) {
        $statistic = $domains->statistics[$rule->id];
        $lines[] = '  ' . $rule->id . ' ' . $statistic->count . ' ' . exampleNotation($context->data->domains, $statistic->first);
    }
    $dead = array_values(array_filter($rules, fn($rule) => $domains->statistics[$rule->id]->count === 0));
    $lines[] = 'dead ' . count($dead);
    foreach ($dead as $rule) {
        $lines[] = '  ' . $rule->id;
    }
    $shadowed = array_values(array_filter($rules, function ($rule) use ($domains) {
        $statistic = $domains->statistics[$rule->id];
        return $rule->parent->algorithm === 'first-applicable' && $statistic->count > 0 && $statistic->count === $statistic->blocked;
    }));
    $lines[] = 'shadowed ' . count($shadowed);
    foreach ($shadowed as $rule) {
        $blockers = $domains->statistics[$rule->id]->blockers;
        $names = [];
        foreach ($rules as $candidate) {
            if (isset($blockers[$candidate->id])) {
                $names[] = $candidate->id;
            }
        }
        $lines[] = '  ' . $rule->id . ' by ' . implode(',', $names);
    }
    $lines[] = 'conflicts ' . count($domains->pairs);
    foreach ($domains->pairs as $pair) {
        $lines[] = '  ' . $pair->policy->id . ' ' . $pair->first->id . ' ' . $pair->second->id . ' ' . $pair->count . ' '
            . conflictWinner($pair->policy, $pair->first, $pair->second)->id;
    }
    return $lines;
}

function coverageLines(object $context, array $records): array
{
    $lines = ['coverage ' . count($records)];
    $uncovered = [];
    foreach ($context->policies->rules as $rule) {
        $symbols = '';
        $count = 0;
        foreach ($records as $record) {
            $symbol = $record->coverage[$rule->id];
            $symbols .= $symbol;
            if ($symbol === 'P' || $symbol === 'D') {
                $count++;
            }
        }
        $lines[] = '  ' . $rule->id . ' ' . $symbols . ' ' . $count;
        if ($count === 0) {
            $uncovered[] = $rule;
        }
    }
    $lines[] = 'uncovered ' . count($uncovered);
    foreach ($uncovered as $rule) {
        $lines[] = '  ' . $rule->id;
    }
    return $lines;
}

function increment(array &$counts, string $key): void
{
    $counts[$key] = ($counts[$key] ?? 0) + 1;
}

function summaryLines(object $context, array $records): array
{
    $decisions = ['PERMIT' => 0, 'DENY' => 0, 'NOT_APPLICABLE' => 0, 'INDETERMINATE' => 0, 'ERROR' => 0];
    $decisive = $obligations = $advice = [];
    $refused = 0;
    foreach ($records as $record) {
        if ($record->error !== null) {
            increment($decisions, 'ERROR');
            continue;
        }
        $result = $record->evaluation;
        increment($decisions, indeterminate($result->decision) ? 'INDETERMINATE' : $result->decision);
        foreach ($record->activations as $activation) {
            if ($activation->reason !== null) {
                $refused++;
            }
        }
        if (definite($result->decision)) {
            increment($decisive, $result->decisive);
        }
        foreach ($result->obligations as $obligation) {
            increment($obligations, $obligation->id);
        }
        foreach ($result->advice as $item) {
            increment($advice, $item->id);
        }
    }
    $lines = ['summary'];
    foreach ($decisions as $name => $count) {
        $lines[] = '  decision ' . $name . ' ' . $count;
    }
    $lines[] = '  refused ' . $refused;
    foreach ($context->policies->elements as $element) {
        if (isset($decisive[$element->id])) {
            $lines[] = '  decisive ' . $element->id . ' ' . $decisive[$element->id];
        }
    }
    ksort($obligations, SORT_STRING);
    ksort($advice, SORT_STRING);
    foreach ($obligations as $id => $count) {
        $lines[] = '  obligation ' . $id . ' ' . $count;
    }
    foreach ($advice as $id => $count) {
        $lines[] = '  advice ' . $id . ' ' . $count;
    }
    return $lines;
}

function analysisLines(object $context, array $records, object $domains): array
{
    $rbac = $context->rbac;
    $lines = ['rbac ' . count($rbac->diagnostics)];
    foreach ($rbac->diagnostics as $diagnostic) {
        $lines[] = '  line ' . $diagnostic->line . ' ' . $diagnostic->keyword . ' ' . $diagnostic->reason;
    }
    $grants = $rbac->permissions;
    usort($grants, fn($a, $b) => strcmp($a->role, $b->role) ?: (strcmp($a->action, $b->action) ?: strcmp($a->type, $b->type)));
    $lines[] = 'grants ' . count($grants);
    foreach ($grants as $grant) {
        $count = 0;
        foreach ($records as $record) {
            if ($record->error === null && $record->granting === $grant->role && $record->request->action === $grant->action && $record->resource->type === $grant->type) {
                $count++;
            }
        }
        $lines[] = '  ' . $grant->role . ' ' . $grant->action . ' ' . $grant->type . ' ' . $count;
    }
    return array_merge($lines, domainLines($context, $domains), coverageLines($context, $records), summaryLines($context, $records));
}

function main(): void
{
    $context = (object) ['rbac' => readRbac(), 'policies' => readPolicies(), 'data' => readAttributes()];
    $records = [];
    foreach (readRequests() as $request) {
        $records[] = evaluateRequest($request, $context, true);
    }
    $domains = analyzeDomains($context);
    $files = ['decisions.txt' => decisionsLines($records), 'traces.txt' => traceLines($records),
        'permissions.txt' => permissionLines($context), 'analysis.txt' => analysisLines($context, $records, $domains)];
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($files as $name => $lines) {
        file_put_contents('output/' . $name, count($lines) ? implode("\n", $lines) . "\n" : '');
    }
}

main();
