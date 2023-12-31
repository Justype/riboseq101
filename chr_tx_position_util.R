isInFrame = function(exon_starts, exon_ends, chr_position, is_5prime = F) {
  # check if this position is in the exons
  # return TRUE if it is in the frame
  
  exon_starts = exon_starts + 1
  if (is_5prime)
    chr_position = chr_position + 1
  
  for (i in 1:length(exon_starts)) {
    if (chr_position >= exon_starts[i] && chr_position <= exon_ends[i])
      return(TRUE)
  }
  
  return(FALSE)
}

.getTxPosition = function(strand, exon_starts, exon_ends, chr_position, is_5prime = F, is_check_frame = F, exon_lengths = NULL) {
  # calculate the transcript position based on strand and chromosome position
  # 5' means 5' of the transcript
  # return tx_position
  # NOTE: xxx_start is 1 nt less than the actual
  #       tx_position is the actual, so you can use this value to slice the DNA sequence
  #       You can provide exon_lengths if this function will be run multiple times on the same gene
  
  # if check and not in exon, return NA
  if (is_check_frame && !isInFrame(exon_starts, exon_ends, chr_position, is_5prime))
    return(NA)
  
  # get the length of each exon
  # xxx_start is 1 nt less than the actual, so we can use end - start to get the length
  if (is.null(exon_lengths))
    exon_lengths = exon_ends - exon_starts
  
  if (strand == "+") {
    # get the rank of chr_position, 2 means on the first exon
    chr_position_rank = ceiling(rank(c(chr_position, exon_starts))[1])
    
    tx_position = chr_position - exon_starts[chr_position_rank - 1] + 1
    
    # if it is not on the 1st exon, add all the lengths of previous exons
    if (chr_position_rank > 2)
      tx_position = tx_position + sum(exon_lengths[1:(chr_position_rank - 2)])
    
    if (!is_5prime)
      tx_position = tx_position - 1
  } else {
    exon_count = length(exon_lengths)
    
    # get the rank of chr_position, length(exon_ends) means on the last exon
    chr_position_rank = floor(rank(c(chr_position, exon_ends))[1])
    
    tx_position = exon_ends[chr_position_rank] - chr_position + 1
    
    # if it is not on the last exon, add all the lengths of subsequent exons
    if (chr_position_rank < exon_count)
      tx_position = tx_position + sum(exon_lengths[(chr_position_rank + 1):exon_count])
    
    # If it is 3', it will be 5' on transcript
    # So it should be 1 nt less to meet the convention
    if (is_5prime)
      tx_position = tx_position - 1
  }
  
  return(tx_position)
}

getTxPositions = function(strand, exon_starts, exon_ends, chr_positions, is_5prime = F, is_check_frame = F) {
  # calculate the transcript positions based on strand and multiple chromosome positions
  # 5' means 5' of the chromosome
  # return tx_positions
  
  exon_lengths = exon_ends - exon_starts
  
  tx_positions = c()
  
  for (i in 1:length(chr_positions))
    tx_positions[i] = .getTxPosition(strand, exon_starts, exon_ends, chr_positions[i], is_5prime, is_check_frame, exon_lengths)
  
  # If on negative strand, reverse the order
  if (strand == "-")
    tx_positions = rev(tx_positions)
  
  return(tx_positions)
}

getFragTxStartEnd = function(strand, exon_starts, exon_ends, chr_start, chr_end, is_sam = F) {
  # calculate the transcript start and end based on strand and chromosome start and end
  # return c(tx_start, tx_end)
  
  # chr_start is 5', chr_end is 3'
  tx_start = .getTxPosition(strand, exon_starts, exon_ends, chr_start, !is_sam)
  tx_end   = .getTxPosition(strand, exon_starts, exon_ends, chr_end, F)
  
  # If it is on negative strand, swap start and end
  if (strand == "-") {
    temp = tx_start
    tx_start = tx_end
    tx_end = temp
  }
  
  return(c(tx_start, tx_end))
}

.getChrPosition = function(strand, exon_starts, exon_ends, tx_position, is_5prime = FALSE, exon_lengths = NULL) {
  # calculate the chromosome position based on strand and transcript position
  # 5' means 5' of the transcript
  # return chr_position
  #       You can provide exon_lengths if this function will be run multiple times on the same gene
  
  # get the length of each exon
  # xxx_start is 1 nt less than the actual, so we can use end - start to get the length
  if (is.null(exon_lengths))
    exon_lengths = exon_ends - exon_starts
  
  if (strand == "+") {
    nth_exon = -1 # store which exon it is in
    
    # search forward
    exon_sum_length = 0
    for (e in 1:length(exon_lengths)) {
      # If tx_position is less than or equal to the sum of 1-n exons
      # , it is in n th exon
      exon_sum_length = exon_sum_length + exon_lengths[e]
      if (tx_position <= exon_sum_length) {
        nth_exon = e
        exon_sum_length = exon_sum_length - exon_lengths[e]
        break
      }
    }
    
    if (nth_exon == -1)
      return(NA) # If the position is larger the length of transcript
    
    chr_position = exon_starts[nth_exon] + tx_position - exon_sum_length
    # exon_starts are the actual position - 1, so no -1 here
    # and subtract all the lengths of previous exons
    
    # if on 5', - 1 to meet the convention
    if(is_5prime)
      chr_position = chr_position - 1
  } else { # - strand
    exon_count = length(exon_lengths)
    nth_exon = -1 # store which exon it is in
    
    # on negative strand: search backwards
    exon_sum_length = 0
    for (e in exon_count:1) {
      # If position is less than or equal to the sum of max-n exons,
      # it is in n th exon
      exon_sum_length = exon_sum_length + exon_lengths[e]
      if (tx_position <= exon_sum_length) {
        nth_exon = e
        exon_sum_length = exon_sum_length - exon_lengths[e]
        break
      }
    }
    
    if (nth_exon == -1)
      return(NA) # If the position is larger the length of transcript
    
    chr_position = exon_ends[nth_exon] - tx_position + 1 + exon_sum_length
    # exon_ends are the actual position, so should + 1 here
    # add all the lengths of subsequent exons
    
    # If on 3' transcript => 5' on - strand chromosome, to meet the convention "-1"
    if(!is_5prime)
      chr_position = chr_position - 1
  }
  
  return(chr_position)
}

getChrPositions = function(strand, exon_starts, exon_ends, tx_positions, is_5prime = FALSE) {
  # calculate the chromosome positions based on strand and multiple transcript positions
  # 5' means 5' of the transcript
  # return chr_positions
  
  exon_lengths = exon_ends - exon_starts
  
  chr_positions = c()
  
  for (i in 1:length(tx_positions))
    chr_positions[i] = .getChrPosition(strand, exon_starts, exon_ends, tx_positions[i], is_5prime, exon_lengths)
  
  # If on negative strand, reverse the order
  if (strand == "-")
    chr_positions = rev(chr_positions)
  
  return(chr_positions)
}

getFragChrStartEnd = function(strand, exon_starts, exon_ends, tx_start, tx_end) {
  # calculate the chromosome start and end based on strand and transcript start and end
  # return c(chr_start, chr_end)
  
  chr_start = .getChrPosition(strand, exon_starts, exon_ends, tx_start, T)
  chr_end   = .getChrPosition(strand, exon_starts, exon_ends, tx_end, F)
  
  # If it is on negative strand, swap start and end
  if (strand == "-") {
    temp = chr_start
    chr_start = chr_end
    chr_end = temp
  }
  
  return(c(chr_start, chr_end))
}
