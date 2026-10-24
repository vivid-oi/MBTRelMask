///|
priv struct SampleCandidate {
  score : String
  key : String
  row : Int32
}

///|
fn sample_compare(a : SampleCandidate, b : SampleCandidate) -> Int32 {
  let order = a.score.lexical_compare(b.score)
  if order == 0 {
    a.key.lexical_compare(b.key)
  } else {
    order
  }
}

///|
/// A max heap retains the k smallest ranks without sorting the population.
fn sample_offer(
  heap : Array[SampleCandidate],
  candidate : SampleCandidate,
  count : Int32,
) -> Unit {
  if count == 0 {
    return
  }
  if heap.length() < count {
    heap.push(candidate)
    let mut position = heap.length() - 1
    while position > 0 {
      let parent = (position - 1) / 2
      if sample_compare(heap[position], heap[parent]) <= 0 {
        break
      }
      let saved = heap[parent]
      heap[parent] = heap[position]
      heap[position] = saved
      position = parent
    }
  } else if sample_compare(candidate, heap[0]) < 0 {
    heap[0] = candidate
    let mut position = 0
    while position * 2 + 1 < heap.length() {
      let left = position * 2 + 1
      let right = left + 1
      let child = if right < heap.length() &&
        sample_compare(heap[right], heap[left]) > 0 {
        right
      } else {
        left
      }
      if sample_compare(heap[position], heap[child]) >= 0 {
        break
      }
      let saved = heap[child]
      heap[child] = heap[position]
      heap[position] = saved
      position = child
    }
  }
}
