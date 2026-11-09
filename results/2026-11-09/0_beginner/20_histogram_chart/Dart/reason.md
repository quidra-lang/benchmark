Use ceiling(count/2), equivalently integer (count+1) divided by 2, only for bar length. Mon 7 yields four stars and Tue 12 yields six. Preserve the original count for the trailing numeric field and keep the current ordered day/count pairing.

The indexed loop preserves names/counts alignment; its named count supplies repetition and the final interpolation independently.

The day/count pair and bar/output expression distinguish scaled bar length from the original trailing count. Nothing in other days changes that local rule.
