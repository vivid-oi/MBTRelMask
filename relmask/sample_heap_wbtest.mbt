///|
test "bounded sample heap matches full sorting including score ties" {
  let candidates = Array::makei(80, i => {
    score: (i * 17 % 13).to_string(),
    key: "key" + i.to_string(),
    row: i,
  })
  let expected = candidates.copy()
  expected.sort_by(sample_compare)
  for count in 0..<=85 {
    for input in [candidates, candidates.rev()] {
      let heap : Array[SampleCandidate] = []
      for candidate in input {
        sample_offer(heap, candidate, count)
        assert_true(heap.length() <= count)
        for i in 1..<heap.length() {
          assert_true(sample_compare(heap[(i - 1) / 2], heap[i]) >= 0)
        }
      }
      heap.sort_by(sample_compare)
      let size = if count < expected.length() {
        count
      } else {
        expected.length()
      }
      assert_eq(heap.length(), size)
      for i in 0..<size {
        assert_eq(heap[i].row, expected[i].row)
      }
    }
  }
}

///|
test "sample score collisions use lexical complete key ordering" {
  let a : SampleCandidate = { score: "same", key: "key10", row: 0, }
  let b : SampleCandidate = { score: "same", key: "key2", row: 1, }
  assert_true(sample_compare(a, b) < 0)
  let heap : Array[SampleCandidate] = []
  sample_offer(heap, b, 1)
  sample_offer(heap, a, 1)
  assert_eq(heap[0].row, 0)
  sample_offer(heap, b, 1)
  assert_eq(heap[0].row, 0)
}
