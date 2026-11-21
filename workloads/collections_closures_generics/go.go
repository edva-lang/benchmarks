package main

import (
	"fmt"
	"os"
	"strconv"
)

type Sample struct {
	id, group, weight, tag int64
}

type Pair struct {
	a, b int64
}

//go:noinline
func composeTwice(f, g func(int64) int64, x int64) int64 {
	y1 := g(f(x))
	return g(f(y1))
}

//go:noinline
func runBatch(bIdx int64) (int64, int64, int64) {
	samples := make([]Sample, 64)
	for k := int64(0); k < 64; k++ {
		idx := bIdx*64 + k
		samples[k] = Sample{
			id:     idx,
			group:  (idx*7 + 3) % 8,
			weight: (idx*31+17)%251 + 1,
			tag:    (idx*13 + 5) % 16,
		}
	}

	filtered := make([]Pair, 0, 64)
	for _, s := range samples {
		if s.group%2 == 0 || s.tag >= 11 {
			filtered = append(filtered, Pair{
				a: s.id % 997,
				b: s.weight * (s.group + 1),
			})
		}
	}

	scale := func(x int64) int64 { return (x*3 + 7) % 10007 }
	shift := func(x int64) int64 { return (x + (bIdx % 97) + 11) % 10007 }

	scores := make([]int64, len(filtered))
	for i, p := range filtered {
		scores[i] = composeTwice(scale, shift, p.a+p.b)
	}

	var foldSum int64
	for _, v := range scores {
		foldSum = (foldSum*33 + v) % 1000000007
	}

	var weightedSum int64
	for _, p := range filtered {
		weightedSum = (weightedSum + p.a*5 + p.b*3) % 1000000007
	}

	var heavyCnt int64
	for _, s := range samples {
		if s.weight > 125 {
			heavyCnt++
		}
	}

	nf := int64(len(filtered))
	bonus := int64(13)
	if heavyCnt > 20 {
		bonus = heavyCnt*19 + nf*7
	}
	digest := (foldSum + weightedSum*17 + bonus) % 1000000007
	return digest, nf, heavyCnt
}

func main() {
	n := int64(16000)
	if len(os.Args) >= 2 {
		if parsed, err := strconv.ParseInt(os.Args[1], 10, 64); err == nil && parsed > 0 {
			n = parsed
		}
	}
	batches := n / 64
	if batches < 1 {
		batches = 1
	}
	var digest, kept, heavy int64
	for b := int64(0); b < batches; b++ {
		bd, bk, bh := runBatch(b)
		digest = (digest*131 + bd) % 1000000007
		kept += bk
		heavy += bh
	}
	fmt.Printf("pipeline=%d,kept=%d,heavy=%d\n", digest, kept, heavy)
}
